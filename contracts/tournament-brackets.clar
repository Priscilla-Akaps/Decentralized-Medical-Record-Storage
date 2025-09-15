;; Tournament Bracket System - Structured Tournament Progression

;; Constants
(define-constant err-owner-only (err u200))
(define-constant err-bracket-not-found (err u202))
(define-constant err-match-not-found (err u203))
(define-constant err-invalid-status (err u204))
(define-constant err-invalid-participants (err u205))
(define-constant err-match-already-played (err u206))
(define-constant err-unauthorized-player (err u207))

;; Data variables
(define-data-var bracket-counter uint u0)
(define-data-var match-counter uint u0)

;; Tournament bracket structure
(define-map tournament-brackets uint {
    tournament-id: uint,
    total-participants: uint,
    bracket-type: (string-ascii 20),
    current-round: uint,
    status: (string-ascii 20),
    winner: (optional principal),
    created-at: uint
})

;; Individual match data
(define-map bracket-matches uint {
    bracket-id: uint,
    round: uint,
    match-number: uint,
    player1: principal,
    player2: principal,
    winner: (optional principal),
    match-status: (string-ascii 20),
    completed-at: (optional uint)
})

;; Player bracket status
(define-map player-bracket-status {bracket-id: uint, player: principal} {
    matches-played: uint,
    matches-won: uint,
    eliminated: bool
})

;; Read-only functions
(define-read-only (get-tournament-bracket (bracket-id uint))
    (map-get? tournament-brackets bracket-id)
)

(define-read-only (get-bracket-match (match-id uint))
    (map-get? bracket-matches match-id)
)

(define-read-only (get-player-bracket-status (bracket-id uint) (player principal))
    (map-get? player-bracket-status {bracket-id: bracket-id, player: player})
)

(define-read-only (get-bracket-counter)
    (var-get bracket-counter)
)

;; Create tournament bracket
(define-public (create-tournament-bracket (tournament-id uint) (participant-count uint))
    (let (
        (bracket-id (+ (var-get bracket-counter) u1))
    )
        ;; Validate inputs
        (asserts! (and (>= participant-count u2) (<= participant-count u16)) err-invalid-participants)
        (asserts! (is-power-of-two participant-count) err-invalid-participants)
        
        ;; Create bracket
        (map-set tournament-brackets bracket-id {
            tournament-id: tournament-id,
            total-participants: participant-count,
            bracket-type: "single-elimination",
            current-round: u1,
            status: "setup",
            winner: none,
            created-at: stacks-block-height
        })
        
        (var-set bracket-counter bracket-id)
        (ok bracket-id)
    )
)

;; Create match
(define-public (create-match (bracket-id uint) (round uint) (match-num uint) (player1 principal) (player2 principal))
    (let (
        (match-id (+ (var-get match-counter) u1))
        (bracket (unwrap! (get-tournament-bracket bracket-id) err-bracket-not-found))
    )
        ;; Validate bracket exists and is in setup
        (asserts! (is-eq (get status bracket) "setup") err-invalid-status)
        
        ;; Create match
        (map-set bracket-matches match-id {
            bracket-id: bracket-id,
            round: round,
            match-number: match-num,
            player1: player1,
            player2: player2,
            winner: none,
            match-status: "pending",
            completed-at: none
        })
        
        ;; Initialize player statuses
        (map-set player-bracket-status {bracket-id: bracket-id, player: player1} {
            matches-played: u0,
            matches-won: u0,
            eliminated: false
        })
        (map-set player-bracket-status {bracket-id: bracket-id, player: player2} {
            matches-played: u0,
            matches-won: u0,
            eliminated: false
        })
        
        (var-set match-counter match-id)
        (ok match-id)
    )
)

;; Start bracket
(define-public (start-tournament-bracket (bracket-id uint))
    (let (
        (bracket (unwrap! (get-tournament-bracket bracket-id) err-bracket-not-found))
    )
        (asserts! (is-eq (get status bracket) "setup") err-invalid-status)
        
        ;; Activate bracket
        (map-set tournament-brackets bracket-id (merge bracket {
            status: "active"
        }))
        
        (ok true)
    )
)

;; Report match result
(define-public (report-match-result (match-id uint) (winner principal))
    (let (
        (match-data (unwrap! (get-bracket-match match-id) err-match-not-found))
        (bracket-id (get bracket-id match-data))
        (bracket (unwrap! (get-tournament-bracket bracket-id) err-bracket-not-found))
        (player1 (get player1 match-data))
        (player2 (get player2 match-data))
    )
        ;; Validate match can be played
        (asserts! (is-eq (get match-status match-data) "pending") err-match-already-played)
        (asserts! (is-eq (get status bracket) "active") err-invalid-status)
        
        ;; Validate winner is one of the players
        (asserts! (or (is-eq winner player1) (is-eq winner player2)) err-unauthorized-player)
        
        ;; Determine loser
        (let (
            (loser (if (is-eq winner player1) player2 player1))
            (winner-status (unwrap! (get-player-bracket-status bracket-id winner) err-bracket-not-found))
            (loser-status (unwrap! (get-player-bracket-status bracket-id loser) err-bracket-not-found))
        )
            ;; Update match
            (map-set bracket-matches match-id (merge match-data {
                winner: (some winner),
                match-status: "completed",
                completed-at: (some stacks-block-height)
            }))
            
            ;; Update winner status
            (map-set player-bracket-status {bracket-id: bracket-id, player: winner} (merge winner-status {
                matches-played: (+ (get matches-played winner-status) u1),
                matches-won: (+ (get matches-won winner-status) u1)
            }))
            
            ;; Update loser status (eliminated)
            (map-set player-bracket-status {bracket-id: bracket-id, player: loser} (merge loser-status {
                matches-played: (+ (get matches-played loser-status) u1),
                eliminated: true
            }))
        )
        
        (ok true)
    )
)

;; Advance to next round
(define-public (advance-bracket-round (bracket-id uint))
    (let (
        (bracket (unwrap! (get-tournament-bracket bracket-id) err-bracket-not-found))
        (current-round (get current-round bracket))
        (next-round (+ current-round u1))
    )
        (asserts! (is-eq (get status bracket) "active") err-invalid-status)
        
        ;; Update bracket round
        (map-set tournament-brackets bracket-id (merge bracket {
            current-round: next-round
        }))
        
        (ok next-round)
    )
)

;; Complete tournament
(define-public (complete-tournament-bracket (bracket-id uint) (winner principal))
    (let (
        (bracket (unwrap! (get-tournament-bracket bracket-id) err-bracket-not-found))
    )
        (asserts! (is-eq (get status bracket) "active") err-invalid-status)
        
        ;; Mark tournament complete
        (map-set tournament-brackets bracket-id (merge bracket {
            status: "completed",
            winner: (some winner)
        }))
        
        (ok true)
    )
)

;; Utility function to check if number is power of two
(define-private (is-power-of-two (n uint))
    (or (is-eq n u2) (or (is-eq n u4) (or (is-eq n u8) (is-eq n u16))))
)
