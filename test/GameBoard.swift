import Foundation
﻿
public class GameBoard {
    let numPlayPiles: Int = 10
    let numDrawPiles: Int = 5
    let startScore: Int = 500

    private var elapsedSeconds: Int
    private var elapsedSecondsLock: object = object()


    var elapsedTimeSpan: TimeSpan {
        get {
            return TimeSpan(0, 0, ElapsedSeconds)
        }
    }
    var elapsedSeconds: Int {
        get {
            lock (elapsedSecondsLock) {
                return elapsedSeconds
            }
        }
        set {
            lock (elapsedSecondsLock) {
                elapsedSeconds = value
            }
        }
    }
    var difficulty: Difficulty 
    var numMoves: Int 
    var score: Int 
    var deck: Deck 
    var playPiles: [[Card]] 
    var drawPiles: [[Card]] 
    var discardPile: [Card] 
    var savedMoves: Stack<Move> 
    var gameBoardEvents: IGameBoardEvents 


    init(difficulty: Difficulty, gameBoardEvents: IGameBoardEvents)
        : this(difficulty, gameBoardEvents, false) {
    }

    init(difficulty: Difficulty, gameBoardEvents: IGameBoardEvents, twoStageCreate: Bool) {
        self.gameBoardEvents = gameBoardEvents
        self.playPiles = [Card][NumPlayPiles]

        for i in 0..<GameBoard.numPlayPiles
            self.playPiles[i] = [Card]()

        self.drawPiles = [[Card]](NumDrawPiles)
        self.discardPile = [Card](Deck.DeckSize)
        self.savedMoves = Stack<Move>()
        self.score = StartScore
        self.difficulty = difficulty
        self.numMoves = 0
        self.elapsedSeconds = 0

        Deck = Deck.Create(difficulty)

        if !twoStageCreate {
            shuffleAndCreateTableau()
        }
    }

    init(xml: Int, gameBoardEvents: IGameBoardEvents) {
        self.gameBoardEvents = gameBoardEvents
        self.savedMoves = Stack<Move>()

        using (StringReader sr = StringReader(xml)) {
            using (XmlReader xr = XmlReader.Create(sr)) {
                GameBoardReaderV1.ReadXml(xr, this)
            }
        }

        if GameBoardEvents != null {
            GameBoardEvents.TableauLoaded(this)
        }
    }@


    func shuffleAndCreateTableau() {
        // This is separate for testing - assert that we haven't created the tableau yet
        assert(Deck.CardsRemaining != 0)

        let actions = [CardAction](Deck.DeckSize * 2)
        let card

        let random = Random((Int)DateTime.Now.Ticks)

        for i in 0..<Deck.DeckSize - 1 {
            Deck.SwapCards(i, random.Next(Deck.DeckSize - i) + i)
        }

        for i in 0..<Deck.Cards.Count {
            card = Deck.Cards[i]
            actions.Add(CardAction(card, CardActionType.Create, card.Location, card.Location = CardLocation(PileType.deck)))
        }

        Score = StartScore

        for cardIndex in 0..<6 {
            for playPileIndex in 0..<GameBoard.numPlayPiles {
                let numCardsInPlayPile = playPileIndex < 4 ? 6 : 5

                if cardIndex > numCardsInPlayPile - 1 {
                    break
                }

                if cardIndex == numCardsInPlayPile - 1 {
                    card = Deck.DealFaceUpCard()
                    PlayPiles[playPileIndex].Add(card)
                } else {
                    card = Deck.DealFaceDownCard()
                    PlayPiles[playPileIndex].Add(card)
                }

                actions.Add(CardAction(
                    card, CardActionType.Move, card.Location, card.Location = CardLocation(PileType.Play, playPileIndex, cardIndex)))
            }
        }

        for drawPileIndex in 0..<GameBoard.numDrawPiles {
            let drawPile = [Card](GameBoard.numPlayPiles)

            DrawPiles.Insert(drawPileIndex, drawPile)

            for j in 0..<GameBoard.numPlayPiles {
                card = Deck.DealFaceDownCard()
                drawPile.Add(card)
                actions.Add(CardAction(
                    card, CardActionType.Move, card.Location, card.Location = CardLocation(PileType.Draw, drawPileIndex, j)))
            }
        }

        assert(Deck.CardsRemaining == 0, "Not all cards were delt")

        if GameBoardEvents != null {
            GameBoardEvents.TableauCreated(this, ReadOnlyCollection<CardAction>(actions))
        }
    }

    func canDealDrawPile() -> Bool {
        for i in 0..<GameBoard.numPlayPiles {
            let playPile = PlayPiles[i]

            if playPile.Count == 0 {
                return false
            }

            // You can only deal a pile if there is a face-up card in the playpile slot
            if !playPile[playPile.Count - 1].FaceUp {
                return false
            }
        }

        return true
    }

    func dealDrawPile() {
        let priorScore = self.score

        Score--
        NumMoves++

        let actions = [CardAction]()
        let drawPile = DrawPiles.Last()

        for cardIndex in (0...playPiles.Length - 1).reverse() {
            // NOTE: Zero is the lowest card in the draw pile
            let card = drawPile[cardIndex]
            let pileIndex = PlayPiles.Length - cardIndex - 1

            card.FaceUp = true
            PlayPiles[pileIndex].Add(card)
            actions.Add(CardAction(
                card, CardActionType.Move, card.Location,
                card.Location = CardLocation(PileType.Play, pileIndex, PlayPiles[pileIndex].Count - 1)))
        }

        DrawPiles.RemoveAt(DrawPiles.Count - 1)

        // Check for discards and subsequence card flips in each of the play piles
        let sideEffects = null

        for i in 0..<GameBoard.numPlayPiles {
            let flippedCard

            if tryAndDiscardCards(i, actions, out flippedCard) {
                if sideEffects == null {
                    sideEffects = DiscardSideEffects[NumPlayPiles]
                }

                sideEffects[i] = DiscardSideEffects.DiscardedAfterDraw | (flippedCard ? DiscardSideEffects.FlipAfterDiscard : 0)
            }
        }

        let move = DrawMove(priorScore, sideEffects)

        self.savedMoves.Push(move)

        if GameBoardEvents != null {
            GameBoardEvents.DrawMoveComplete(ReadOnlyCollection<CardAction>(actions))
        }
    }

    func dragCardsBetweenPiles(toPileIndex: Int, fromPileIndex: Int, fromCardIndex: Int) {
#if DEBUG
        if fromPileIndex == toPileIndex {
            throw ArgumentException("Cannot drag cards to the same pile")
        }
#endif

        let actions = [CardAction]()
        let fromPile = PlayPiles[fromPileIndex]
        let toPile = PlayPiles[toPileIndex]

        // Keep the play piles consistent by moving the cards into
        // a holding list instead of moving them one at a time.
        let dragPile = fromPile.GetRange(fromCardIndex, fromPile.Count - fromCardIndex)

        fromPile.RemoveRange(fromCardIndex, dragPile.Count)

        for i in 0..<dragPile.Count {
            let card = dragPile[i]

            toPile.Add(card)
            actions.Add(
                CardAction(card, CardActionType.Move, card.Location,
                    card.Location = CardLocation(PileType.Play, toPileIndex, toPile.Count - 1)))
        }

        let flippedAfterDrag = flipBottomCardFaceUp(fromPileIndex, actions)

        // Remove cards to discard pile?
        let flippedAfterDiscard
        let discardedCards = tryAndDiscardCards(toPileIndex, actions, out flippedAfterDiscard)

        SavedMoves.Push(DragMove(self.score, fromPileIndex, toPileIndex, dragPile.Count,
            (flippedAfterDrag ? DragMoveSideEffects.FlipAfterDrag : DragMoveSideEffects.None) |
            (discardedCards ? DragMoveSideEffects.DiscardedAfterDrag : DragMoveSideEffects.None) |
            (flippedAfterDiscard ? DragMoveSideEffects.FlipAfterDiscard : DragMoveSideEffects.None)))

        NumMoves++
        Score--

        if GameBoardEvents != null {
            GameBoardEvents.DragMoveComplete(ReadOnlyCollection<CardAction>(actions))
        }
    }

    func isGameWon() -> Bool {
        return DiscardPile.Count == Deck.DeckSize
    }

    func canDragCard(pileIndex: Int, cardIndex: Int) -> Bool {
        return cardIndex >= getFirstDraggableCardIndex(pileIndex)
    }

    func getFirstDraggableCardIndex(pileIndex: Int) -> Int {
        let cardIndex = PlayPiles[pileIndex].Count - 1

        if cardIndex <= 0 {
            return cardIndex
        }

        for i in (0...cardIndex - 1).reverse() {
            let card = PlayPiles[pileIndex][i]

            if !card.FaceUp {
                return cardIndex
            }

            let cardNext = PlayPiles[pileIndex][cardIndex]

            if cardNext.Suit != card.Suit ||
                cardNext.Ordinal != card.Ordinal - 1 {
                return cardIndex
            }

            cardIndex = i
        }

        return cardIndex
    }

    func canDropDragPile(toPileIndex: Int, fromPileIndex: Int, fromCardIndex: Int) -> Bool {
        let playPile = PlayPiles[toPileIndex]

        if playPile.Count == 0 {
            return true
        }

        let playCard = playPile[playPile.Count - 1]

        if !playCard.FaceUp {
            return false
        }

        return canDropCardOnPlayCard(playCard, PlayPiles[fromPileIndex][fromCardIndex])
    }

    func clearUndoStack() {
        SavedMoves.Clear()
    }

    func undoLastMove() {
        while (SavedMoves.Count > 0) {
            let move = SavedMoves.Pop()

            if move is DragMove {
                undoDragMove((DragMove)move)
                break
            }
            else if move is DrawMove {
                undoDrawMove((DrawMove)move)
                break
            } else {
                assert(false)
            }
        }
    }

    func undoDragMove(move: DragMove) {
        let actions = [CardAction]()
        let toPile = PlayPiles[move.ToPileIndex]
        let fromPile = PlayPiles[move.FromPileIndex]
        let card

        if move.SideEffects & DragMoveSideEffects.FlipAfterDiscard) != 0 {
            flipBottomCardFaceDown(move.ToPileIndex, actions {
        }
    }

        if move.SideEffects & DragMoveSideEffects.DiscardedAfterDrag) != 0 {
            returnCards(move.ToPileIndex, actions {
        }
    }

        if move.SideEffects & DragMoveSideEffects.FlipAfterDrag) != 0 {
            flipBottomCardFaceDown(move.FromPileIndex, actions {
        }
    }

        // Move dragged cards into holding list
        let index = toPile.Count - move.NumCardsDragged
        let dragPile = toPile.GetRange(index, move.NumCardsDragged)

        toPile.RemoveRange(index, move.NumCardsDragged)

        for i in 0..<dragPile.Count {
            card = dragPile[i]
            fromPile.Add(card)
            actions.Add(CardAction(
                card, CardActionType.Move, card.Location,
                card.Location = CardLocation(PileType.Play, move.FromPileIndex, fromPile.Count - 1)))
        }

        Score = move.PriorScore
        NumMoves++

        if GameBoardEvents != null {
            GameBoardEvents.UndoDragMoveComplete(ReadOnlyCollection<CardAction>(actions))
        }
    }

    func undoDrawMove(move: DrawMove) {
        let actions = [CardAction]()

        if move.SideEffects != null {
            for i in 0..<move.SideEffects.Count {
                if move.SideEffects[i] & DiscardSideEffects.DiscardedAfterDraw) != 0 {
                    if ((move.SideEffects[i] & DiscardSideEffects.FlipAfterDiscard) != 0 {
                        flipBottomCardFaceDown(i, actions)
                    }

                    returnCards(i, actions)
                }
            }
        }

        let drawPile = [Card](GameBoard.numPlayPiles)

        DrawPiles.Add(drawPile)

        for pileIndex in (0...playPiles.Length - 1).reverse() {
            let fromPile = PlayPiles[pileIndex]
            let card = fromPile.Last()
            let cardIndex = PlayPiles.Length- 1 - pileIndex 

            drawPile.Add(card)
            fromPile.RemoveAt(fromPile.Count - 1)

            actions.Add(
                CardAction(card, CardActionType.Move, card.Location,
                    card.Location = CardLocation(PileType.Draw, DrawPiles.Count - 1, cardIndex)))
        }

        self.score = move.PriorScore
        self.numMoves++

        if GameBoardEvents != null {
            GameBoardEvents.UndoDrawMoveComplete(ReadOnlyCollection<CardAction>(actions))
        }
    }

    func canDiscardCards(pileIndex: Int) -> Bool {
        let playPile = PlayPiles[pileIndex]

        if playPile.Count < (Int)Rank.King {
            return false
        }

        let discardSuit = playPile[playPile.Count - 1].Suit

        for (Int i = 1; i <= (Int)Rank.King; i++) {
            let card = playPile[playPile.Count - i]

            if !card.FaceUp || card.Rank != (Rank)i || card.Suit != discardSuit {
                return false
            }
        }

        return true
    }

    func tryAndDiscardCards(fromPileIndex: Int, actions: [CardAction], Bool: out) -> Bool {
        flippedCard = false

        if !canDiscardCards(fromPileIndex) {
            return false
        }

        Score += 100

        let fromPile = PlayPiles[fromPileIndex]
        let fromCardIndex = fromPile.Count - (Int)Rank.King
        let discardPile = fromPile.GetRange(fromCardIndex, (Int)Rank.King)

        fromPile.RemoveRange(fromCardIndex, (Int)Rank.King)

        for i in 0..<discardPile.Count {
            let card = discardPile[i]

            self.discardPile.Add(card)

            actions.Add(
                CardAction(card, CardActionType.Move, card.Location,
                    card.Location = CardLocation(PileType.Discard, 0, self.discardPile.Count - 1)))
        }

        flippedCard = flipBottomCardFaceUp(fromPileIndex, actions)

        return true
    }

    func returnCards(toPileIndex: Int, actions: [CardAction]) {
        let fromCardIndex = DiscardPile.Count - (Int)Rank.King
        let returnPile = DiscardPile.GetRange(fromCardIndex, (Int)Rank.King)

        DiscardPile.RemoveRange(fromCardIndex, (Int)Rank.King)

        for i in 0..<returnPile.Count {
            let card = returnPile[i]

            self.playPiles[toPileIndex].Add(card)

            actions.Add(CardAction(
                card, CardActionType.Move, card.Location,
                card.Location = CardLocation(PileType.Play, toPileIndex, self.playPiles[toPileIndex].Count - 1)))
        }
    }

    func flipBottomCardFaceDown(pileIndex: Int, actions: [CardAction]) {
        let playPile = PlayPiles[pileIndex]

        let index = playPile.Count - 1
        let card = playPile[index]

        card.FaceUp = false

        actions.Add(CardAction(card, CardActionType.Flip))
    }

    func flipBottomCardFaceUp(pileIndex: Int, actions: [CardAction]) -> Bool {
        let playPile = PlayPiles[pileIndex]

        if playPile.Count == 0 {
            return false
        }

        let index = playPile.Count - 1
        let card = playPile[index]

        if card.FaceUp {
            return false
        }

        card.FaceUp = true

        actions.Add(CardAction(card, CardActionType.Flip))

        return true
    }

    func canDropCardOnPlayCard(playCard: Card, dropCard: Card) -> Bool {
        return (Int)playCard.Rank == (Int)dropCard.Rank + 1
    }

    func getHints() -> [Hint] {
        let hintMoves = [Hint]()

        for i in 0..<PlayPiles.Length {
            for j in 0..<PlayPiles[i].Count {
                for k in 0..<PlayPiles.Length {
                    if k == i {
                        continue
                    }

                    if canDragCard(i, j) && // The card can be moved
                        PlayPiles[k].Count > 0 && // Pile is not empty
                        !(j > 0 && canDropCardOnPlayCard(PlayPiles[i][j - 1], PlayPiles[i][j])) && // Don't break an existing run
                        canDropCardOnPlayCard(PlayPiles[k].Last(), PlayPiles[i][j])) // Can move the card to another pile {
                        hintMoves.Add(Hint(i, k, PlayPiles[i].Count - j) {
                    }
                }
                }
            }
        }

        if hintMoves.Count == 0 {
            // Look for an empty playpile
            let toPileIndex = -1

            for i in 0..<PlayPiles.Length {
                if PlayPiles[i].Count == 0 {
                    toPileIndex = i
                    break
                }
            }

            if toPileIndex != -1 {
                // Got one...
                let pileLength = 0
                let fromPileIndex = -1
                let longestFaceDownRun = 0

                // Look for the play pile with the most face down cards
                for i in 0..<NumPlayPiles {
                    let faceDownRun = PlayPiles[i].Count(c => !c.FaceUp)

                    if faceDownRun > longestFaceDownRun {
                        longestFaceDownRun = faceDownRun
                        fromPileIndex = i
                    }
                }

                if fromPileIndex == -1 {
                    let mostCards = 0

                    // No face down cards, just use the pile with the most cards
                    // and just remove the top card
                    // TODO-john-2012: This could be improved to remove as many cards
                    // as possible, unless the entire pile is a run in which case
                    // switch pick another pile.
                    for i in 0..<NumPlayPiles {
                        if PlayPiles[i].Count > mostCards {
                            mostCards = PlayPiles[i].Count
                            fromPileIndex = i
                            pileLength = 1
                        }
                    }
                } else {
                    // We have a from pile with face down cards, take as many cards off it as possible
                    for (Int j = PlayPiles[fromPileIndex].Count - 1; j > 0; j--) {
                        if canDragCard(fromPileIndex, j) {
                            pileLength = PlayPiles[fromPileIndex].Count - j
                        }
                        else if !PlayPiles[fromPileIndex][j].FaceUp {
                            break
                        }
                    }
                }

                if fromPileIndex == -1 {
                    // New game...
                }
                    return hintMoves

                hintMoves.Add(Hint(fromPileIndex, toPileIndex, pileLength))
            }
        }

        if hintMoves.Count == 0 && DrawPiles.Count > 0 {
            // Draw pile
            hintMoves.Add(Hint(-1, -1, NumPlayPiles))
        }

        return hintMoves
    }

    func toString() -> Int {
        let sb = StringBuilder()

        try {
            using (XmlWriter writer = XmlWriter.Create(sb)) {
                GameBoardWriter.WriteXml(writer, this)
            }
        }
        catch (Exception) {
        }

        return sb.toString()
    }

}

