;; Identity Reputation System
;; Tracks reputation scores based on verification history and community trust

;; Data Maps
(define-map identity-reputation-scores
    { identity-id: uint }
    {
        base-score: uint,
        verification-score: uint,
        community-score: uint,
        total-score: uint,
        last-updated: uint,
        decay-applied: uint
    }
)

(define-map verification-history
    { identity-id: uint }
    {
        total-verifications: uint,
        unique-verifiers: uint,
        trusted-verifiers: uint,
        recent-verifications: uint,
        first-verification: uint
    }
)

(define-map community-ratings
    { identity-id: uint, rater: principal }
    {
        rating: uint,
        timestamp: uint,
        weight: uint
    }
)

(define-map trust-network
    { identity-id: uint, trusted-by: uint }
    {
        trust-level: uint,
        established-at: uint,
        interaction-count: uint
    }
)

(define-map reputation-metrics
    { identity-id: uint }
    {
        interactions: uint,
        positive-feedback: uint,
        negative-feedback: uint,
        consistency-score: uint,
        longevity-bonus: uint
    }
)

;; Constants
(define-constant MAX-REPUTATION-SCORE u1000)
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)
(define-constant REPUTATION-DECAY-RATE u5)
(define-constant DECAY-PERIOD-BLOCKS u1440) ;; ~10 days
(define-constant TRUSTED-VERIFIER-BONUS u50)
(define-constant COMMUNITY-WEIGHT u3)

;; Error Constants
(define-constant ERR-IDENTITY-NOT-FOUND u1001)
(define-constant ERR-INVALID-RATING u1002)
(define-constant ERR-SELF-RATING u1003)
(define-constant ERR-ALREADY-RATED u1004)
(define-constant ERR-UNAUTHORIZED u1005)

;; Public Functions

;; Initialize reputation for a new identity
(define-public (initialize-reputation (identity-id uint))
    (begin
        (map-set identity-reputation-scores
            { identity-id: identity-id }
            {
                base-score: u100,
                verification-score: u0,
                community-score: u0,
                total-score: u100,
                last-updated: stacks-block-height,
                decay-applied: stacks-block-height
            }
        )
        (map-set verification-history
            { identity-id: identity-id }
            {
                total-verifications: u0,
                unique-verifiers: u0,
                trusted-verifiers: u0,
                recent-verifications: u0,
                first-verification: u0
            }
        )
        (map-set reputation-metrics
            { identity-id: identity-id }
            {
                interactions: u0,
                positive-feedback: u0,
                negative-feedback: u0,
                consistency-score: u100,
                longevity-bonus: u0
            }
        )
        (ok true)
    )
)

;; Record a verification and update reputation
(define-public (record-verification (identity-id uint) (verifier-identity-id uint) (is-trusted-verifier bool))
    (let
        (
            (history (get-verification-history identity-id))
            (reputation (get-reputation-score identity-id))
        )
        (map-set verification-history
            { identity-id: identity-id }
            {
                total-verifications: (+ (get total-verifications history) u1),
                unique-verifiers: (+ (get unique-verifiers history) u1),
                trusted-verifiers: (if is-trusted-verifier (+ (get trusted-verifiers history) u1) (get trusted-verifiers history)),
                recent-verifications: (+ (get recent-verifications history) u1),
                first-verification: (if (is-eq (get first-verification history) u0) stacks-block-height (get first-verification history))
            }
        )
        (unwrap! (update-reputation-score identity-id) (err u1006))
        (ok true)
    )
)

;; Submit community rating
(define-public (submit-rating (identity-id uint) (rating uint) (rater-identity-id uint))
    (let
        (
            (existing-rating (map-get? community-ratings { identity-id: identity-id, rater: tx-sender }))
        )
        (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) (err ERR-INVALID-RATING))
        (asserts! (not (is-eq identity-id rater-identity-id)) (err ERR-SELF-RATING))
        (asserts! (is-none existing-rating) (err ERR-ALREADY-RATED))
        
        (map-set community-ratings
            { identity-id: identity-id, rater: tx-sender }
            {
                rating: rating,
                timestamp: stacks-block-height,
                weight: COMMUNITY-WEIGHT
            }
        )
        (unwrap! (update-community-score identity-id) (err u1007))
        (unwrap! (record-interaction identity-id (> rating u3)) (err u1008))
        (ok true)
    )
)

;; Establish trust relationship
(define-public (establish-trust (identity-id uint) (trusted-by-id uint) (trust-level uint))
    (begin
        (map-set trust-network
            { identity-id: identity-id, trusted-by: trusted-by-id }
            {
                trust-level: trust-level,
                established-at: stacks-block-height,
                interaction-count: u1
            }
        )
        (unwrap! (update-reputation-score identity-id) (err u1006))
        (ok true)
    )
)

;; Apply reputation decay
(define-public (apply-reputation-decay (identity-id uint))
    (let
        (
            (reputation (get-reputation-score identity-id))
            (blocks-since-decay (- stacks-block-height (get decay-applied reputation)))
        )
        (if (>= blocks-since-decay DECAY-PERIOD-BLOCKS)
            (let
                (
                    (decay-amount (/ (get total-score reputation) REPUTATION-DECAY-RATE))
                    (new-total (if (> (get total-score reputation) decay-amount) 
                                  (- (get total-score reputation) decay-amount) 
                                  u50))
                )
                (map-set identity-reputation-scores
                    { identity-id: identity-id }
                    (merge reputation 
                        { 
                            total-score: new-total,
                            decay-applied: stacks-block-height,
                            last-updated: stacks-block-height
                        }
                    )
                )
                (ok true)
            )
            (ok false)
        )
    )
)

;; Read-only Functions

(define-read-only (get-reputation-score (identity-id uint))
    (default-to
        {
            base-score: u0,
            verification-score: u0,
            community-score: u0,
            total-score: u0,
            last-updated: u0,
            decay-applied: u0
        }
        (map-get? identity-reputation-scores { identity-id: identity-id })
    )
)

(define-read-only (get-verification-history (identity-id uint))
    (default-to
        {
            total-verifications: u0,
            unique-verifiers: u0,
            trusted-verifiers: u0,
            recent-verifications: u0,
            first-verification: u0
        }
        (map-get? verification-history { identity-id: identity-id })
    )
)

(define-read-only (get-community-rating (identity-id uint) (rater principal))
    (map-get? community-ratings { identity-id: identity-id, rater: rater })
)

(define-read-only (get-trust-relationship (identity-id uint) (trusted-by uint))
    (map-get? trust-network { identity-id: identity-id, trusted-by: trusted-by })
)

(define-read-only (get-reputation-metrics (identity-id uint))
    (default-to
        {
            interactions: u0,
            positive-feedback: u0,
            negative-feedback: u0,
            consistency-score: u0,
            longevity-bonus: u0
        }
        (map-get? reputation-metrics { identity-id: identity-id })
    )
)

;; Private Functions

(define-private (update-reputation-score (identity-id uint))
    (let
        (
            (reputation (get-reputation-score identity-id))
            (history (get-verification-history identity-id))
            (metrics (get-reputation-metrics identity-id))
            (verification-score (calculate-verification-score history))
            (community-score (get community-score reputation))
            (longevity-bonus (calculate-longevity-bonus history))
            (new-total (+ (+ (get base-score reputation) verification-score) 
                         (+ community-score longevity-bonus)))
        )
        (map-set identity-reputation-scores
            { identity-id: identity-id }
            (merge reputation
                {
                    verification-score: verification-score,
                    total-score: (if (> new-total MAX-REPUTATION-SCORE) MAX-REPUTATION-SCORE new-total),
                    last-updated: stacks-block-height
                }
            )
        )
        (ok true)
    )
)

(define-private (calculate-verification-score (history (tuple (total-verifications uint) (unique-verifiers uint) (trusted-verifiers uint) (recent-verifications uint) (first-verification uint))))
    (let
        (
            (base-verification-score (* (get unique-verifiers history) u10))
            (trusted-bonus (* (get trusted-verifiers history) TRUSTED-VERIFIER-BONUS))
            (recent-activity-bonus (if (> (get recent-verifications history) u5) u25 u0))
        )
        (+ (+ base-verification-score trusted-bonus) recent-activity-bonus)
    )
)

(define-private (calculate-longevity-bonus (history (tuple (total-verifications uint) (unique-verifiers uint) (trusted-verifiers uint) (recent-verifications uint) (first-verification uint))))
    (if (> (get first-verification history) u0)
        (let
            (
                (blocks-active (- stacks-block-height (get first-verification history)))
                (longevity-score (/ blocks-active u1000)) ;; 1 point per ~1000 blocks
            )
            (if (> longevity-score u100) u100 longevity-score)
        )
        u0
    )
)

(define-private (update-community-score (identity-id uint))
    (let
        (
            (reputation (get-reputation-score identity-id))
            (metrics (get-reputation-metrics identity-id))
            (positive-ratio (if (> (get interactions metrics) u0)
                               (/ (* (get positive-feedback metrics) u100) (get interactions metrics))
                               u50))
            (community-score (* positive-ratio u2)) ;; Scale factor
        )
        (map-set identity-reputation-scores
            { identity-id: identity-id }
            (merge reputation { community-score: community-score })
        )
        (ok true)
    )
)

(define-private (record-interaction (identity-id uint) (is-positive bool))
    (let
        (
            (metrics (get-reputation-metrics identity-id))
        )
        (map-set reputation-metrics
            { identity-id: identity-id }
            (merge metrics
                {
                    interactions: (+ (get interactions metrics) u1),
                    positive-feedback: (if is-positive (+ (get positive-feedback metrics) u1) (get positive-feedback metrics)),
                    negative-feedback: (if (not is-positive) (+ (get negative-feedback metrics) u1) (get negative-feedback metrics))
                }
            )
        )
        (ok true)
    )
)
