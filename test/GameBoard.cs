using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Linq;
using System.Collections.ObjectModel;

namespace Jamoki.Games.Spider
{
    public class GameBoard
    {
        #region Fields
        public const int NumPlayPiles = 10;
        public const int NumDrawPiles = 5;
        public const int StartScore = 500;

        private int elapsedSeconds;
        private object elapsedSecondsLock = new object();

        #endregion

        #region Properties
        public TimeSpan ElapsedTimeSpan
        {
            get
            {
                return new TimeSpan(0, 0, ElapsedSeconds);
            }
        }
        public int ElapsedSeconds
        {
            get
            {
                lock (elapsedSecondsLock)
                {
                    return elapsedSeconds;
                }
            }
            set
            {
                lock (elapsedSecondsLock)
                {
                    elapsedSeconds = value;
                }
            }
        }
        public Difficulty Difficulty { get; set; }
        public int NumMoves { get; set; }
        public int Score { get; set; }
        public Deck Deck { get; set; }
        public List<Card>[] PlayPiles { get; set; }
        public List<List<Card>> DrawPiles { get; set; }
        public List<Card> DiscardPile { get; set; }
        public Stack<Move> SavedMoves { get; set; }
        public IGameBoardEvents GameBoardEvents { get; set; }

        #endregion

        #region Construction
        public GameBoard(Difficulty difficulty, IGameBoardEvents gameBoardEvents)
            : this(difficulty, gameBoardEvents, false)
        {
        }

        public GameBoard(Difficulty difficulty, IGameBoardEvents gameBoardEvents, bool twoStageCreate)
        {
            this.GameBoardEvents = gameBoardEvents;
            this.PlayPiles = new List<Card>[NumPlayPiles];

            for (int i = 0; i < GameBoard.NumPlayPiles; i++)
                this.PlayPiles[i] = new List<Card>();

            this.DrawPiles = new List<List<Card>>(NumDrawPiles);
            this.DiscardPile = new List<Card>(Deck.DeckSize);
            this.SavedMoves = new Stack<Move>();
            this.Score = StartScore;
            this.Difficulty = difficulty;
            this.NumMoves = 0;
            this.ElapsedSeconds = 0;

            Deck = Deck.Create(difficulty);

            if (!twoStageCreate)
                ShuffleAndCreateTableau();
        }

        public GameBoard(string xml, IGameBoardEvents gameBoardEvents)
        {
            this.GameBoardEvents = gameBoardEvents;
            this.SavedMoves = new Stack<Move>();

            using (StringReader sr = new StringReader(xml))
            {
                using (XmlReader xr = XmlReader.Create(sr))
                {
                    GameBoardReaderV1.ReadXml(xr, this);
                }
            }

            if (GameBoardEvents != null)
                GameBoardEvents.TableauLoaded(this);
        }

        #endregion

        #region Methods
        public void ShuffleAndCreateTableau()
        {
            // This is separate for testing - assert that we haven't created the tableau yet
            Debug.Assert(Deck.CardsRemaining != 0);

            List<CardAction> actions = new List<CardAction>(Deck.DeckSize * 2);
            Card card;

            Random random = new Random((int)DateTime.Now.Ticks);

            for (int i = 0; i < Deck.DeckSize - 1; i++)
            {
                Deck.SwapCards(i, random.Next(Deck.DeckSize - i) + i);
            }

            for (int i = 0; i < Deck.Cards.Count; i++)
            {
                card = Deck.Cards[i];
                actions.Add(new CardAction(card, CardActionType.Create, card.Location, card.Location = new CardLocation(PileType.Deck)));
            }

            Score = StartScore;

            for (int cardIndex = 0; cardIndex < 6; cardIndex++)
            {
                for (int playPileIndex = 0; playPileIndex < GameBoard.NumPlayPiles; playPileIndex++)
                {
                    int numCardsInPlayPile = playPileIndex < 4 ? 6 : 5;

                    if (cardIndex > numCardsInPlayPile - 1)
                        break;

                    if (cardIndex == numCardsInPlayPile - 1)
                    {
                        card = Deck.DealFaceUpCard();
                        PlayPiles[playPileIndex].Add(card);
                    }
                    else
                    {
                        card = Deck.DealFaceDownCard();
                        PlayPiles[playPileIndex].Add(card);
                    }

                    actions.Add(new CardAction(
                        card, CardActionType.Move, card.Location, card.Location = new CardLocation(PileType.Play, playPileIndex, cardIndex)));
                }
            }

            for (int drawPileIndex = 0; drawPileIndex < GameBoard.NumDrawPiles; drawPileIndex++)
            {
                List<Card> drawPile = new List<Card>(GameBoard.NumPlayPiles);

                DrawPiles.Insert(drawPileIndex, drawPile);

                for (int j = 0; j < GameBoard.NumPlayPiles; j++)
                {
                    card = Deck.DealFaceDownCard();
                    drawPile.Add(card);
                    actions.Add(new CardAction(
                        card, CardActionType.Move, card.Location, card.Location = new CardLocation(PileType.Draw, drawPileIndex, j)));
                }
            }

            Debug.Assert(Deck.CardsRemaining == 0, "Not all cards were delt");

            if (GameBoardEvents != null)
                GameBoardEvents.TableauCreated(this, new ReadOnlyCollection<CardAction>(actions));
        }

        public bool CanDealDrawPile()
        {
            for (int i = 0; i < GameBoard.NumPlayPiles; i++)
            {
                List<Card> playPile = PlayPiles[i];

                if (playPile.Count == 0)
                    return false;

                // You can only deal a pile if there is a face-up card in the playpile slot
                if (!playPile[playPile.Count - 1].FaceUp)
                    return false;
            }

            return true;
        }

        public void DealDrawPile()
        {
            int priorScore = this.Score;

            Score--;
            NumMoves++;

            List<CardAction> actions = new List<CardAction>();
            List<Card> drawPile = DrawPiles.Last();

            for (int cardIndex = PlayPiles.Length - 1; cardIndex >= 0; cardIndex--)
            {
                // NOTE: Zero is the lowest card in the draw pile
                Card card = drawPile[cardIndex];
                int pileIndex = PlayPiles.Length - cardIndex - 1;

                card.FaceUp = true;
                PlayPiles[pileIndex].Add(card);
                actions.Add(new CardAction(
                    card, CardActionType.Move, card.Location,
                    card.Location = new CardLocation(PileType.Play, pileIndex, PlayPiles[pileIndex].Count - 1)));
            }

            DrawPiles.RemoveAt(DrawPiles.Count - 1);

            // Check for discards and subsequence card flips in each of the play piles
            DiscardSideEffects[] sideEffects = null;

            for (int i = 0; i < GameBoard.NumPlayPiles; i++)
            {
                bool flippedCard;

                if (TryAndDiscardCards(i, actions, out flippedCard))
                {
                    if (sideEffects == null)
                    {
                        sideEffects = new DiscardSideEffects[NumPlayPiles];
                    }

                    sideEffects[i] = DiscardSideEffects.DiscardedAfterDraw | (flippedCard ? DiscardSideEffects.FlipAfterDiscard : 0);
                }
            }

            Move move = new DrawMove(priorScore, sideEffects);

            this.SavedMoves.Push(move);

            if (GameBoardEvents != null)
                GameBoardEvents.DrawMoveComplete(new ReadOnlyCollection<CardAction>(actions));
        }

        public void DragCardsBetweenPiles(int toPileIndex, int fromPileIndex, int fromCardIndex)
        {
#if DEBUG
            if (fromPileIndex == toPileIndex)
                throw new ArgumentException("Cannot drag cards to the same pile");
#endif

            List<CardAction> actions = new List<CardAction>();
            List<Card> fromPile = PlayPiles[fromPileIndex];
            List<Card> toPile = PlayPiles[toPileIndex];

            // Keep the play piles consistent by moving the cards into
            // a holding list instead of moving them one at a time.
            List<Card> dragPile = fromPile.GetRange(fromCardIndex, fromPile.Count - fromCardIndex);

            fromPile.RemoveRange(fromCardIndex, dragPile.Count);

            for (int i = 0; i < dragPile.Count; i++)
            {
                Card card = dragPile[i];

                toPile.Add(card);
                actions.Add(
                    new CardAction(card, CardActionType.Move, card.Location,
                        card.Location = new CardLocation(PileType.Play, toPileIndex, toPile.Count - 1)));
            }

            bool flippedAfterDrag = FlipBottomCardFaceUp(fromPileIndex, actions);

            // Remove cards to discard pile?
            bool flippedAfterDiscard;
            bool discardedCards = TryAndDiscardCards(toPileIndex, actions, out flippedAfterDiscard);

            SavedMoves.Push(new DragMove(this.Score, fromPileIndex, toPileIndex, dragPile.Count,
                (flippedAfterDrag ? DragMoveSideEffects.FlipAfterDrag : DragMoveSideEffects.None) |
                (discardedCards ? DragMoveSideEffects.DiscardedAfterDrag : DragMoveSideEffects.None) |
                (flippedAfterDiscard ? DragMoveSideEffects.FlipAfterDiscard : DragMoveSideEffects.None)));

            NumMoves++;
            Score--;

            if (GameBoardEvents != null)
                GameBoardEvents.DragMoveComplete(new ReadOnlyCollection<CardAction>(actions));
        }

        public bool IsGameWon()
        {
            return DiscardPile.Count == Deck.DeckSize;
        }

        public bool CanDragCard(int pileIndex, int cardIndex)
        {
            return cardIndex >= GetFirstDraggableCardIndex(pileIndex);
        }

        public int GetFirstDraggableCardIndex(int pileIndex)
        {
            int cardIndex = PlayPiles[pileIndex].Count - 1;

            if (cardIndex <= 0)
                return cardIndex;

            for (int i = cardIndex - 1; i >= 0; i--)
            {
                Card card = PlayPiles[pileIndex][i];

                if (!card.FaceUp)
                    return cardIndex;

                Card cardNext = PlayPiles[pileIndex][cardIndex];

                if (cardNext.Suit != card.Suit ||
                    cardNext.Ordinal != card.Ordinal - 1)
                    return cardIndex;

                cardIndex = i;
            }

            return cardIndex;
        }

        public bool CanDropDragPile(int toPileIndex, int fromPileIndex, int fromCardIndex)
        {
            List<Card> playPile = PlayPiles[toPileIndex];

            if (playPile.Count == 0)
                return true;

            Card playCard = playPile[playPile.Count - 1];

            if (!playCard.FaceUp)
                return false;

            return CanDropCardOnPlayCard(playCard, PlayPiles[fromPileIndex][fromCardIndex]);
        }

        public void ClearUndoStack()
        {
            SavedMoves.Clear();
        }

        public void UndoLastMove()
        {
            while (SavedMoves.Count > 0)
            {
                Move move = SavedMoves.Pop();

                if (move is DragMove)
                {
                    UndoDragMove((DragMove)move);
                    break;
                }
                else if (move is DrawMove)
                {
                    UndoDrawMove((DrawMove)move);
                    break;
                }
                else
                {
                    Debug.Assert(false);
                }
            }
        }

        public void UndoDragMove(DragMove move)
        {
            List<CardAction> actions = new List<CardAction>();
            List<Card> toPile = PlayPiles[move.ToPileIndex];
            List<Card> fromPile = PlayPiles[move.FromPileIndex];
            Card card;

            if ((move.SideEffects & DragMoveSideEffects.FlipAfterDiscard) != 0)
            {
                FlipBottomCardFaceDown(move.ToPileIndex, actions);
            }

            if ((move.SideEffects & DragMoveSideEffects.DiscardedAfterDrag) != 0)
            {
                ReturnCards(move.ToPileIndex, actions);
            }

            if ((move.SideEffects & DragMoveSideEffects.FlipAfterDrag) != 0)
            {
                FlipBottomCardFaceDown(move.FromPileIndex, actions);
            }

            // Move dragged cards into holding list
            int index = toPile.Count - move.NumCardsDragged;
            List<Card> dragPile = toPile.GetRange(index, move.NumCardsDragged);

            toPile.RemoveRange(index, move.NumCardsDragged);

            for (int i = 0; i < dragPile.Count; i++)
            {
                card = dragPile[i];
                fromPile.Add(card);
                actions.Add(new CardAction(
                    card, CardActionType.Move, card.Location,
                    card.Location = new CardLocation(PileType.Play, move.FromPileIndex, fromPile.Count - 1)));
            }

            Score = move.PriorScore;
            NumMoves++;

            if (GameBoardEvents != null)
                GameBoardEvents.UndoDragMoveComplete(new ReadOnlyCollection<CardAction>(actions));
        }

        private void UndoDrawMove(DrawMove move)
        {
            List<CardAction> actions = new List<CardAction>();

            if (move.SideEffects != null)
            {
                for (int i = 0; i < move.SideEffects.Count; i++)
                {
                    if ((move.SideEffects[i] & DiscardSideEffects.DiscardedAfterDraw) != 0)
                    {
                        if ((move.SideEffects[i] & DiscardSideEffects.FlipAfterDiscard) != 0)
                            FlipBottomCardFaceDown(i, actions);

                        ReturnCards(i, actions);
                    }
                }
            }

            List<Card> drawPile = new List<Card>(GameBoard.NumPlayPiles);

            DrawPiles.Add(drawPile);

            for (int pileIndex = PlayPiles.Length - 1; pileIndex >= 0; pileIndex--)
            {
                List<Card> fromPile = PlayPiles[pileIndex];
                Card card = fromPile.Last();
                int cardIndex = PlayPiles.Length- 1 - pileIndex ;

                drawPile.Add(card);
                fromPile.RemoveAt(fromPile.Count - 1);

                actions.Add(
                    new CardAction(card, CardActionType.Move, card.Location,
                        card.Location = new CardLocation(PileType.Draw, DrawPiles.Count - 1, cardIndex)));
            }

            this.Score = move.PriorScore;
            this.NumMoves++;

            if (GameBoardEvents != null)
                GameBoardEvents.UndoDrawMoveComplete(new ReadOnlyCollection<CardAction>(actions));
        }

        private bool CanDiscardCards(int pileIndex)
        {
            List<Card> playPile = PlayPiles[pileIndex];

            if (playPile.Count < (int)Rank.King)
                return false;

            Suit discardSuit = playPile[playPile.Count - 1].Suit;

            for (int i = 1; i <= (int)Rank.King; i++)
            {
                Card card = playPile[playPile.Count - i];

                if (!card.FaceUp || card.Rank != (Rank)i || card.Suit != discardSuit)
                    return false;
            }

            return true;
        }

        private bool TryAndDiscardCards(int fromPileIndex, List<CardAction> actions, out bool flippedCard)
        {
            flippedCard = false;

            if (!CanDiscardCards(fromPileIndex))
                return false;

            Score += 100;

            List<Card> fromPile = PlayPiles[fromPileIndex];
            int fromCardIndex = fromPile.Count - (int)Rank.King;
            List<Card> discardPile = fromPile.GetRange(fromCardIndex, (int)Rank.King);

            fromPile.RemoveRange(fromCardIndex, (int)Rank.King);

            for (int i = 0; i < discardPile.Count; i++)
            {
                Card card = discardPile[i];

                this.DiscardPile.Add(card);

                actions.Add(
                    new CardAction(card, CardActionType.Move, card.Location,
                        card.Location = new CardLocation(PileType.Discard, 0, this.DiscardPile.Count - 1)));
            }

            flippedCard = FlipBottomCardFaceUp(fromPileIndex, actions);

            return true;
        }

        private void ReturnCards(int toPileIndex, List<CardAction> actions)
        {
            int fromCardIndex = DiscardPile.Count - (int)Rank.King;
            List<Card> returnPile = DiscardPile.GetRange(fromCardIndex, (int)Rank.King);

            DiscardPile.RemoveRange(fromCardIndex, (int)Rank.King);

            for (int i = 0; i < returnPile.Count; i++)
            {
                Card card = returnPile[i];

                this.PlayPiles[toPileIndex].Add(card);

                actions.Add(new CardAction(
                    card, CardActionType.Move, card.Location,
                    card.Location = new CardLocation(PileType.Play, toPileIndex, this.PlayPiles[toPileIndex].Count - 1)));
            }
        }

        private void FlipBottomCardFaceDown(int pileIndex, List<CardAction> actions)
        {
            List<Card> playPile = PlayPiles[pileIndex];

            int index = playPile.Count - 1;
            Card card = playPile[index];

            card.FaceUp = false;

            actions.Add(new CardAction(card, CardActionType.Flip));
        }

        private bool FlipBottomCardFaceUp(int pileIndex, List<CardAction> actions)
        {
            List<Card> playPile = PlayPiles[pileIndex];

            if (playPile.Count == 0)
                return false;

            int index = playPile.Count - 1;
            Card card = playPile[index];

            if (card.FaceUp)
                return false;

            card.FaceUp = true;

            actions.Add(new CardAction(card, CardActionType.Flip));

            return true;
        }

        private bool CanDropCardOnPlayCard(Card playCard, Card dropCard)
        {
            return (int)playCard.Rank == (int)dropCard.Rank + 1;
        }

        public IList<Hint> GetHints()
        {
            List<Hint> hintMoves = new List<Hint>();

            for (int i = 0; i < PlayPiles.Length; i++)
            {
                for (int j = 0; j < PlayPiles[i].Count; j++)
                {
                    for (int k = 0; k < PlayPiles.Length; k++)
                    {
                        if (k == i)
                            continue;

                        if (CanDragCard(i, j) && // The card can be moved
                            PlayPiles[k].Count > 0 && // Pile is not empty
                            !(j > 0 && CanDropCardOnPlayCard(PlayPiles[i][j - 1], PlayPiles[i][j])) && // Don't break an existing run
                            CanDropCardOnPlayCard(PlayPiles[k].Last(), PlayPiles[i][j])) // Can move the card to another pile
                        {
                            hintMoves.Add(new Hint(i, k, PlayPiles[i].Count - j));
                        }
                    }
                }
            }

            if (hintMoves.Count == 0)
            {
                // Look for an empty playpile
                int toPileIndex = -1;

                for (int i = 0; i < PlayPiles.Length; i++)
                {
                    if (PlayPiles[i].Count == 0)
                    {
                        toPileIndex = i;
                        break;
                    }
                }

                if (toPileIndex != -1)
                {
                    // Got one...
                    int pileLength = 0;
                    int fromPileIndex = -1;
                    int longestFaceDownRun = 0;

                    // Look for the play pile with the most face down cards
                    for (int i = 0; i < NumPlayPiles; i++)
                    {
                        int faceDownRun = PlayPiles[i].Count(c => !c.FaceUp);

                        if (faceDownRun > longestFaceDownRun)
                        {
                            longestFaceDownRun = faceDownRun;
                            fromPileIndex = i;
                        }
                    }

                    if (fromPileIndex == -1)
                    {
                        int mostCards = 0;

                        // No face down cards, just use the pile with the most cards
                        // and just remove the top card
                        // TODO-john-2012: This could be improved to remove as many cards
                        // as possible, unless the entire pile is a run in which case
                        // switch pick another pile.
                        for (int i = 0; i < NumPlayPiles; i++)
                        {
                            if (PlayPiles[i].Count > mostCards)
                            {
                                mostCards = PlayPiles[i].Count;
                                fromPileIndex = i;
                                pileLength = 1;
                            }
                        }
                    }
                    else
                    {
                        // We have a from pile with face down cards, take as many cards off it as possible
                        for (int j = PlayPiles[fromPileIndex].Count - 1; j > 0; j--)
                        {
                            if (CanDragCard(fromPileIndex, j))
                                pileLength = PlayPiles[fromPileIndex].Count - j;
                            else if (!PlayPiles[fromPileIndex][j].FaceUp)
                                break;
                        }
                    }

                    if (fromPileIndex == -1)
                        // New game...
                        return hintMoves;

                    hintMoves.Add(new Hint(fromPileIndex, toPileIndex, pileLength));
                }
            }

            if (hintMoves.Count == 0 && DrawPiles.Count > 0)
            {
                // Draw pile
                hintMoves.Add(new Hint(-1, -1, NumPlayPiles));
            }

            return hintMoves;
        }

        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();

            try
            {
                using (XmlWriter writer = XmlWriter.Create(sb))
                {
                    GameBoardWriter.WriteXml(writer, this);
                }
            }
            catch (Exception)
            {
            }

            return sb.ToString();
        }

        #endregion
    }
}
