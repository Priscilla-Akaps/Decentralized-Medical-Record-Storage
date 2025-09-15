;; Learning Badges NFT System
;; Collectible achievement badges for language learning milestones

(define-non-fungible-token learning-badge uint)

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-BADGE-TYPES u50)

;; Error constants
(define-constant ERR-NOT-AUTHORIZED u300)
(define-constant ERR-BADGE-NOT-FOUND u301)
(define-constant ERR-ALREADY-EARNED u302)
(define-constant ERR-REQUIREMENTS-NOT-MET u303)
(define-constant ERR-INVALID-BADGE-TYPE u304)
(define-constant ERR-BADGE-TYPE-EXISTS u305)

;; Badge rarity levels
(define-constant RARITY-COMMON u1)
(define-constant RARITY-UNCOMMON u2)
(define-constant RARITY-RARE u3)
(define-constant RARITY-EPIC u4)
(define-constant RARITY-LEGENDARY u5)

;; Data variables
(define-data-var next-badge-id uint u1)
(define-data-var next-badge-type-id uint u1)
(define-data-var total-badges-minted uint u0)

;; Badge types define what badges can be earned
(define-map badge-types uint
    {
        name: (string-ascii 100),
        description: (string-ascii 200),
        rarity: uint,
        requirement-type: (string-ascii 50),
        requirement-value: uint,
        active: bool,
        total-minted: uint,
        max-supply: uint,
        created-by: principal
    }
)

;; Individual badge instances
(define-map badge-instances uint
    {
        owner: principal,
        badge-type-id: uint,
        earned-at: uint,
        earned-for: (string-ascii 100),
        metadata: (string-ascii 500)
    }
)

;; User badge collections
(define-map user-badge-collections principal
    {
        total-badges: uint,
        common-badges: uint,
        uncommon-badges: uint,
        rare-badges: uint,
        epic-badges: uint,
        legendary-badges: uint,
        achievement-points: uint,
        first-badge-earned: (optional uint)
    }
)

;; Badge earning history
(define-map badge-earning-log {user: principal, badge-type-id: uint}
    {
        badge-id: uint,
        earned-at: uint,
        context: (string-ascii 100)
    }
)

;; Public Functions

;; Create a new badge type (admin only)
(define-public (create-badge-type
    (name (string-ascii 100))
    (description (string-ascii 200))
    (rarity uint)
    (requirement-type (string-ascii 50))
    (requirement-value uint)
    (max-supply uint))
    (let
        (
            (badge-type-id (var-get next-badge-type-id))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-NOT-AUTHORIZED))
        (asserts! (and (>= rarity RARITY-COMMON) (<= rarity RARITY-LEGENDARY)) (err ERR-INVALID-BADGE-TYPE))
        (asserts! (> (len name) u0) (err ERR-INVALID-BADGE-TYPE))
        
        (map-set badge-types badge-type-id
            {
                name: name,
                description: description,
                rarity: rarity,
                requirement-type: requirement-type,
                requirement-value: requirement-value,
                active: true,
                total-minted: u0,
                max-supply: max-supply,
                created-by: tx-sender
            }
        )
        
        (var-set next-badge-type-id (+ badge-type-id u1))
        (ok badge-type-id)
    )
)

;; Award a badge to a user
(define-public (award-badge (user principal) (badge-type-id uint) (context (string-ascii 100)))
    (let
        (
            (badge-type (unwrap! (map-get? badge-types badge-type-id) (err ERR-BADGE-NOT-FOUND)))
            (badge-id (var-get next-badge-id))
            (existing-earn (map-get? badge-earning-log {user: user, badge-type-id: badge-type-id}))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-NOT-AUTHORIZED))
        (asserts! (get active badge-type) (err ERR-BADGE-NOT-FOUND))
        (asserts! (is-none existing-earn) (err ERR-ALREADY-EARNED))
        (asserts! (< (get total-minted badge-type) (get max-supply badge-type)) (err ERR-REQUIREMENTS-NOT-MET))
        
        ;; Mint the NFT badge
        (try! (nft-mint? learning-badge badge-id user))
        
        ;; Create badge instance
        (map-set badge-instances badge-id
            {
                owner: user,
                badge-type-id: badge-type-id,
                earned-at: stacks-block-height,
                earned-for: context,
                metadata: (get description badge-type)
            }
        )
        
        ;; Log the earning
        (map-set badge-earning-log {user: user, badge-type-id: badge-type-id}
            {
                badge-id: badge-id,
                earned-at: stacks-block-height,
                context: context
            }
        )
        
        ;; Update badge type stats
        (map-set badge-types badge-type-id
            (merge badge-type {total-minted: (+ (get total-minted badge-type) u1)})
        )
        
        ;; Update user collection
        (unwrap! (update-user-collection user (get rarity badge-type)) (err u999))
        
        ;; Increment counters
        (var-set next-badge-id (+ badge-id u1))
        (var-set total-badges-minted (+ (var-get total-badges-minted) u1))
        
        (ok badge-id)
    )
)

;; Check if user can earn a specific badge
(define-public (check-badge-eligibility (user principal) (badge-type-id uint) (user-stats-lessons uint) (user-stats-streak uint) (user-stats-tokens uint))
    (let
        (
            (badge-type (unwrap! (map-get? badge-types badge-type-id) (err ERR-BADGE-NOT-FOUND)))
            (existing-earn (map-get? badge-earning-log {user: user, badge-type-id: badge-type-id}))
            (requirement-type (get requirement-type badge-type))
            (requirement-value (get requirement-value badge-type))
        )
        (asserts! (get active badge-type) (err ERR-BADGE-NOT-FOUND))
        (asserts! (is-none existing-earn) (err ERR-ALREADY-EARNED))
        (asserts! (< (get total-minted badge-type) (get max-supply badge-type)) (err ERR-REQUIREMENTS-NOT-MET))
        
        (let
            (
                (meets-requirement (cond
                    ((is-eq requirement-type "lessons")) (>= user-stats-lessons requirement-value)
                    ((is-eq requirement-type "streak")) (>= user-stats-streak requirement-value)
                    ((is-eq requirement-type "tokens")) (>= user-stats-tokens requirement-value)
                    (true) false
                ))
            )
            (ok meets-requirement)
        )
    )
)

;; Auto-award badges based on achievements
(define-public (process-achievement-badges (user principal) (lessons-completed uint) (current-streak uint) (total-tokens uint))
    (let
        (
            (starter-badge (try! (try-award-badge-if-eligible user u1 lessons-completed current-streak total-tokens "First Steps")))
            (lesson-master (try! (try-award-badge-if-eligible user u2 lessons-completed current-streak total-tokens "Lesson Master")))
            (streak-warrior (try! (try-award-badge-if-eligible user u3 lessons-completed current-streak total-tokens "Streak Warrior")))
        )
        (ok true)
    )
)

;; Transfer badge (NFT transfer)
(define-public (transfer-badge (badge-id uint) (recipient principal))
    (let
        (
            (badge (unwrap! (map-get? badge-instances badge-id) (err ERR-BADGE-NOT-FOUND)))
            (current-owner (unwrap! (nft-get-owner? learning-badge badge-id) (err ERR-BADGE-NOT-FOUND)))
        )
        (asserts! (is-eq tx-sender current-owner) (err ERR-NOT-AUTHORIZED))
        
        (try! (nft-transfer? learning-badge badge-id current-owner recipient))
        
        (map-set badge-instances badge-id
            (merge badge {owner: recipient})
        )
        
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-badge-type (badge-type-id uint))
    (map-get? badge-types badge-type-id)
)

(define-read-only (get-badge-instance (badge-id uint))
    (map-get? badge-instances badge-id)
)

(define-read-only (get-user-badge-collection (user principal))
    (default-to
        {
            total-badges: u0,
            common-badges: u0,
            uncommon-badges: u0,
            rare-badges: u0,
            epic-badges: u0,
            legendary-badges: u0,
            achievement-points: u0,
            first-badge-earned: none
        }
        (map-get? user-badge-collections user)
    )
)

(define-read-only (has-earned-badge (user principal) (badge-type-id uint))
    (is-some (map-get? badge-earning-log {user: user, badge-type-id: badge-type-id}))
)

(define-read-only (get-badge-earning-history (user principal) (badge-type-id uint))
    (map-get? badge-earning-log {user: user, badge-type-id: badge-type-id})
)

(define-read-only (get-badge-rarity-name (rarity uint))
    (if (is-eq rarity RARITY-LEGENDARY) "Legendary"
        (if (is-eq rarity RARITY-EPIC) "Epic"
            (if (is-eq rarity RARITY-RARE) "Rare"
                (if (is-eq rarity RARITY-UNCOMMON) "Uncommon" "Common"))))
)

(define-read-only (calculate-collection-value (user principal))
    (let
        (
            (collection (get-user-badge-collection user))
        )
        (+ 
            (* (get common-badges collection) u1)
            (+ (* (get uncommon-badges collection) u3)
               (+ (* (get rare-badges collection) u10)
                  (+ (* (get epic-badges collection) u25)
                     (* (get legendary-badges collection) u100))))
        )
    )
)

(define-read-only (get-system-stats)
    {
        total-badge-types: (var-get next-badge-type-id),
        total-badges-minted: (var-get total-badges-minted),
        next-badge-id: (var-get next-badge-id)
    }
)

;; Private functions

(define-private (update-user-collection (user principal) (rarity uint))
    (let
        (
            (current-collection (get-user-badge-collection user))
            (achievement-points (calculate-points-for-rarity rarity))
            (is-first-badge (is-eq (get total-badges current-collection) u0))
        )
        (map-set user-badge-collections user
            {
                total-badges: (+ (get total-badges current-collection) u1),
                common-badges: (if (is-eq rarity RARITY-COMMON) (+ (get common-badges current-collection) u1) (get common-badges current-collection)),
                uncommon-badges: (if (is-eq rarity RARITY-UNCOMMON) (+ (get uncommon-badges current-collection) u1) (get uncommon-badges current-collection)),
                rare-badges: (if (is-eq rarity RARITY-RARE) (+ (get rare-badges current-collection) u1) (get rare-badges current-collection)),
                epic-badges: (if (is-eq rarity RARITY-EPIC) (+ (get epic-badges current-collection) u1) (get epic-badges current-collection)),
                legendary-badges: (if (is-eq rarity RARITY-LEGENDARY) (+ (get legendary-badges current-collection) u1) (get legendary-badges current-collection)),
                achievement-points: (+ (get achievement-points current-collection) achievement-points),
                first-badge-earned: (if is-first-badge (some stacks-block-height) (get first-badge-earned current-collection))
            }
        )
        (ok true)
    )
)

(define-private (calculate-points-for-rarity (rarity uint))
    (if (is-eq rarity RARITY-LEGENDARY) u100
        (if (is-eq rarity RARITY-EPIC) u25
            (if (is-eq rarity RARITY-RARE) u10
                (if (is-eq rarity RARITY-UNCOMMON) u3 u1))))
)

(define-private (try-award-badge-if-eligible (user principal) (badge-type-id uint) (lessons uint) (streak uint) (tokens uint) (context (string-ascii 100)))
    (match (check-badge-eligibility user badge-type-id lessons streak tokens)
        eligible (if eligible (award-badge user badge-type-id context) (ok u0))
        error-code (ok u0)
    )
)
