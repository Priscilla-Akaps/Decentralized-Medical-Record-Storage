;; Royalty Streaming Contract - Subscription-Based Creator Support
;; Enables continuous royalty payments through flexible streaming tiers

;; Constants  
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u700))
(define-constant ERR_STREAM_NOT_FOUND (err u701))
(define-constant ERR_INSUFFICIENT_BALANCE (err u702))
(define-constant ERR_INVALID_TIER (err u703))
(define-constant ERR_SUBSCRIPTION_EXPIRED (err u704))
(define-constant ERR_STREAM_PAUSED (err u705))
(define-constant ERR_INVALID_AMOUNT (err u706))

;; Stream tier definitions
(define-map stream-tiers
    { tier-id: uint }
    { 
        name: (string-ascii 32),
        price-per-block: uint,
        min-commitment: uint,
        benefits: (string-ascii 64),
        active: bool
    }
)

;; Creator stream configurations  
(define-map creator-streams
    { creator: principal }
    {
        stream-name: (string-ascii 50),
        available-tiers: (list 5 uint),
        total-subscribers: uint,
        total-earned: uint,
        is-active: bool,
        created-at: uint
    }
)

;; Individual subscriptions
(define-map subscriptions
    { subscriber: principal, creator: principal }
    {
        tier-id: uint,
        start-block: uint,
        next-payment: uint,
        total-paid: uint,
        auto-renew: bool,
        subscription-status: uint
    }
)

;; Payment streams tracking
(define-map active-streams
    { stream-id: uint }
    {
        creator: principal,
        subscriber: principal, 
        rate-per-block: uint,
        last-claim: uint,
        stream-balance: uint,
        end-block: uint
    }
)

;; Data variables
(define-data-var next-stream-id uint u1)
(define-data-var platform-fee-rate uint u250)
(define-data-var streaming-paused bool false)

;; Setup subscription tiers
(define-public (create-subscription-tier 
    (tier-id uint) 
    (name (string-ascii 32))
    (price-per-block uint) 
    (min-commitment uint)
    (benefits (string-ascii 64)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> price-per-block u0) ERR_INVALID_AMOUNT)
        (ok (map-set stream-tiers
            { tier-id: tier-id }
            {
                name: name,
                price-per-block: price-per-block,
                min-commitment: min-commitment, 
                benefits: benefits,
                active: true
            }))))

;; Create creator streaming profile
(define-public (setup-creator-stream 
    (stream-name (string-ascii 50))
    (tier-list (list 5 uint)))
    (begin
        (asserts! (not (var-get streaming-paused)) ERR_STREAM_PAUSED)
        (ok (map-set creator-streams
            { creator: tx-sender }
            {
                stream-name: stream-name,
                available-tiers: tier-list,
                total-subscribers: u0,
                total-earned: u0,
                is-active: true,
                created-at: stacks-block-height
            }))))

;; Subscribe to creator stream
(define-public (subscribe-to-stream (creator principal) (tier-id uint) (commitment-blocks uint))
    (let ((tier-info (unwrap! (map-get? stream-tiers { tier-id: tier-id }) ERR_INVALID_TIER))
          (creator-stream (unwrap! (map-get? creator-streams { creator: creator }) ERR_STREAM_NOT_FOUND))
          (stream-id (var-get next-stream-id)))
        (asserts! (get active tier-info) ERR_INVALID_TIER)
        (asserts! (get is-active creator-stream) ERR_STREAM_NOT_FOUND)
        (asserts! (>= commitment-blocks (get min-commitment tier-info)) ERR_INVALID_AMOUNT)
        
        ;; Create subscription
        (map-set subscriptions
            { subscriber: tx-sender, creator: creator }
            {
                tier-id: tier-id,
                start-block: stacks-block-height,
                next-payment: (+ stacks-block-height commitment-blocks),
                total-paid: u0,
                auto-renew: true,
                subscription-status: u1
            })
            
        ;; Create active stream
        (map-set active-streams
            { stream-id: stream-id }
            {
                creator: creator,
                subscriber: tx-sender,
                rate-per-block: (get price-per-block tier-info),
                last-claim: stacks-block-height,
                stream-balance: (* (get price-per-block tier-info) commitment-blocks),
                end-block: (+ stacks-block-height commitment-blocks)
            })
            
        ;; Update creator stats
        (map-set creator-streams
            { creator: creator }
            (merge creator-stream {
                total-subscribers: (+ (get total-subscribers creator-stream) u1)
            }))
            
        (var-set next-stream-id (+ stream-id u1))
        (ok stream-id)))

;; Claim streaming payments
(define-public (claim-stream-payment (stream-id uint))
    (let ((stream (unwrap! (map-get? active-streams { stream-id: stream-id }) ERR_STREAM_NOT_FOUND))
          (blocks-elapsed (- stacks-block-height (get last-claim stream)))
          (payment-amount (* (get rate-per-block stream) blocks-elapsed))
          (platform-fee (/ (* payment-amount (var-get platform-fee-rate)) u10000)))
        (asserts! (is-eq tx-sender (get creator stream)) ERR_NOT_AUTHORIZED)
        (asserts! (>= stacks-block-height (get last-claim stream)) ERR_INVALID_AMOUNT)
        (asserts! (<= stacks-block-height (get end-block stream)) ERR_SUBSCRIPTION_EXPIRED)
        
        ;; Update stream data
        (map-set active-streams
            { stream-id: stream-id }
            (merge stream {
                last-claim: stacks-block-height,
                stream-balance: (- (get stream-balance stream) payment-amount)
            }))
            
        ;; Update creator earnings
        (let ((creator-stream (unwrap! (map-get? creator-streams { creator: tx-sender }) ERR_STREAM_NOT_FOUND)))
            (map-set creator-streams
                { creator: tx-sender }
                (merge creator-stream {
                    total-earned: (+ (get total-earned creator-stream) (- payment-amount platform-fee))
                })))
        (ok (- payment-amount platform-fee))))

;; Upgrade subscription tier  
(define-public (upgrade-subscription (creator principal) (new-tier-id uint))
    (let ((current-sub (unwrap! (map-get? subscriptions { subscriber: tx-sender, creator: creator }) ERR_STREAM_NOT_FOUND))
          (new-tier (unwrap! (map-get? stream-tiers { tier-id: new-tier-id }) ERR_INVALID_TIER)))
        (asserts! (get active new-tier) ERR_INVALID_TIER)
        (asserts! (is-eq (get subscription-status current-sub) u1) ERR_SUBSCRIPTION_EXPIRED)
        
        (ok (map-set subscriptions
            { subscriber: tx-sender, creator: creator }
            (merge current-sub { tier-id: new-tier-id })))))

;; Cancel subscription
(define-public (cancel-subscription (creator principal))
    (let ((subscription (unwrap! (map-get? subscriptions { subscriber: tx-sender, creator: creator }) ERR_STREAM_NOT_FOUND))
          (creator-stream (unwrap! (map-get? creator-streams { creator: creator }) ERR_STREAM_NOT_FOUND)))
        (map-set subscriptions
            { subscriber: tx-sender, creator: creator }
            (merge subscription { 
                subscription-status: u2,
                auto-renew: false 
            }))
        (map-set creator-streams
            { creator: creator }
            (merge creator-stream {
                total-subscribers: (- (get total-subscribers creator-stream) u1)
            }))
        (ok true)))

;; Read-only functions
(define-read-only (get-subscription-info (subscriber principal) (creator principal))
    (map-get? subscriptions { subscriber: subscriber, creator: creator }))

(define-read-only (get-creator-stream (creator principal))
    (map-get? creator-streams { creator: creator }))

(define-read-only (get-tier-info (tier-id uint))
    (map-get? stream-tiers { tier-id: tier-id }))

(define-read-only (get-stream-details (stream-id uint))
    (map-get? active-streams { stream-id: stream-id }))

(define-read-only (calculate-streaming-cost (tier-id uint) (duration-blocks uint))
    (let ((tier (unwrap! (map-get? stream-tiers { tier-id: tier-id }) u0)))
        (* (get price-per-block tier) duration-blocks)))

;; Admin functions
(define-public (toggle-streaming-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (ok (var-set streaming-paused (not (var-get streaming-paused))))))

(define-public (update-platform-fee (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT)
        (ok (var-set platform-fee-rate new-rate))))

(define-read-only (get-platform-stats)
    {
        total-streams: (- (var-get next-stream-id) u1),
        platform-fee: (var-get platform-fee-rate),
        streaming-active: (not (var-get streaming-paused))
    })
