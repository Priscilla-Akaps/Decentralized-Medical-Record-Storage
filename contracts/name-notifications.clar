;; Name Expiration Notification System
;; Allows users to subscribe to notifications for name expirations

;; Contract owner and configuration
(define-data-var owner principal tx-sender)
(define-data-var notification-fee uint u50000) ;; 0.05 STX in microSTX

;; Constants
(define-constant DEFAULT_REMINDER_PERIOD u1440) ;; 24 hours in blocks (10 min blocks)
(define-constant MAX_REMINDER_PERIOD u10080) ;; 7 days in blocks
(define-constant ERR_UNAUTHORIZED u1001)
(define-constant ERR_INVALID_PERIOD u1002)
(define-constant ERR_INSUFFICIENT_PAYMENT u1003)
(define-constant ERR_ALREADY_SUBSCRIBED u1004)

;; Data maps
(define-map name-expiration-dates (string-ascii 50) uint)
(define-map notification-subscriptions 
  {name: (string-ascii 50), subscriber: principal} 
  {reminder-period: uint, created-at: uint, active: bool})
(define-map user-notification-count principal uint)

;; Admin functions
(define-public (set-notification-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err ERR_UNAUTHORIZED))
    (var-set notification-fee new-fee)
    (ok true)))

;; Set name expiration date (callable by name registry or owner)
(define-public (set-name-expiration (name (string-ascii 50)) (expiration-date uint))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err ERR_UNAUTHORIZED))
    (map-set name-expiration-dates name expiration-date)
    (ok true)))

;; Subscribe to expiration notifications for a name
(define-public (subscribe-to-expiration (name (string-ascii 50)) (reminder-period uint))
  (let ((subscription-key {name: name, subscriber: tx-sender})
        (current-count (default-to u0 (map-get? user-notification-count tx-sender))))
    (asserts! (and (>= reminder-period u1) (<= reminder-period MAX_REMINDER_PERIOD)) (err ERR_INVALID_PERIOD))
    (asserts! (is-none (map-get? notification-subscriptions subscription-key)) (err ERR_ALREADY_SUBSCRIBED))
    
    ;; Payment for notification service
    (try! (stx-transfer? (var-get notification-fee) tx-sender (var-get owner)))
    
    ;; Create subscription
    (map-set notification-subscriptions subscription-key
      {reminder-period: reminder-period, created-at: block-height, active: true})
    
    ;; Update user notification count
    (map-set user-notification-count tx-sender (+ current-count u1))
    
    (ok true)))

;; Cancel notification subscription
(define-public (cancel-subscription (name (string-ascii 50)))
  (let ((subscription-key {name: name, subscriber: tx-sender})
        (subscription (map-get? notification-subscriptions subscription-key))
        (current-count (default-to u0 (map-get? user-notification-count tx-sender))))
    (match subscription
      sub-data 
        (begin
          (map-set notification-subscriptions subscription-key
            (merge sub-data {active: false}))
          (if (> current-count u0)
            (map-set user-notification-count tx-sender (- current-count u1))
            true)
          (ok true))
      (err ERR_UNAUTHORIZED))))

;; Check if a name needs notification (read-only)
(define-read-only (check-expiration-reminder (name (string-ascii 50)) (subscriber principal))
  (let ((subscription-key {name: name, subscriber: subscriber})
        (subscription (map-get? notification-subscriptions subscription-key))
        (expiration-date (map-get? name-expiration-dates name)))
    (match subscription
      sub-data 
        (match expiration-date
          exp-date
            (let ((reminder-block (- exp-date (get reminder-period sub-data))))
              (if (and (get active sub-data) (>= block-height reminder-block) (< block-height exp-date))
                (some {reminder-due: true, expiration-date: exp-date, reminder-period: (get reminder-period sub-data)})
                none))
          none)
      none)))

;; Get all active subscriptions for a user (read-only)
(define-read-only (get-user-subscriptions (user principal))
  (map-get? user-notification-count user))

;; Get name expiration date (read-only)  
(define-read-only (get-name-expiration (name (string-ascii 50)))
  (map-get? name-expiration-dates name))

;; Get subscription details (read-only)
(define-read-only (get-subscription (name (string-ascii 50)) (subscriber principal))
  (map-get? notification-subscriptions {name: name, subscriber: subscriber}))

;; Check if name is expiring soon (read-only)
(define-read-only (is-name-expiring-soon (name (string-ascii 50)) (days-ahead uint))
  (let ((expiration-date (map-get? name-expiration-dates name))
        (check-date (+ block-height (* days-ahead u144)))) ;; Approx 144 blocks per day
    (match expiration-date
      exp-date 
        (if (<= exp-date check-date)
          (some {expiring: true, expiration-date: exp-date, blocks-remaining: (if (> exp-date block-height) (- exp-date block-height) u0)})
          (some {expiring: false, expiration-date: exp-date, blocks-remaining: (- exp-date block-height)}))
      none)))

;; Batch set expiration dates (admin only)
(define-public (batch-set-expirations (names-and-dates (list 10 {name: (string-ascii 50), expiration: uint})))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err ERR_UNAUTHORIZED))
    (fold set-single-expiration names-and-dates (ok true))))

(define-private (set-single-expiration (name-data {name: (string-ascii 50), expiration: uint}) (previous-result (response bool uint)))
  (if (is-ok previous-result)
    (begin
      (map-set name-expiration-dates (get name name-data) (get expiration name-data))
      (ok true))
    previous-result))

;; Get current notification fee
(define-read-only (get-notification-fee)
  (var-get notification-fee))

;; Get contract statistics
(define-read-only (get-stats)
  {notification-fee: (var-get notification-fee), 
   owner: (var-get owner),
   max-reminder-period: MAX_REMINDER_PERIOD,
   default-reminder-period: DEFAULT_REMINDER_PERIOD})
