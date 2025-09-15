;; Dynamic Name Pricing Contract
;; Market-based pricing using length, composition, and demand metrics

;; Data variables
(define-data-var owner principal tx-sender)
(define-data-var registry (optional principal) none)
(define-data-var base-price uint u1000000)
(define-data-var ph-index uint u0)

;; Constants
(define-constant EPOCH_LEN u100)
(define-constant EPOCH_WINDOW u12)
(define-constant PH_CAP u1000)
(define-constant SCALE u1000)
(define-constant DEMAND_WEIGHT_1 u10)
(define-constant DEMAND_WEIGHT_2 u5)
(define-constant ERR_UNAUTHORIZED u1001)
(define-constant ERR_NO_REGISTRY u1002)

;; Data maps
(define-map bucket-total uint {reg: uint, trans: uint})
(define-map bucket-epoch {b: uint, e: uint} {reg: uint, trans: uint})
(define-map price-history uint {name: (string-ascii 48), price: uint, block: uint, kind: uint})

;; Helper functions (ordered to avoid circular dependencies)
(define-private (get-length-multiplier (len uint))
  (if (<= len u3) u3000 (if (<= len u5) u2000 (if (<= len u8) u1500 u1000))))

(define-private (char-is-alnum (c uint))
  (or (and (>= c 48) (<= c 57)) (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122))))

(define-private (char-is-dash-under (c uint))
  (or (is-eq c 45) (is-eq c 95)))

(define-private (get-comp-type (name (string-ascii 50)) (i uint) (len uint))
  (if (>= i len) u0
    (let ((c (unwrap-panic (element-at name i))))
      (if (char-is-alnum c)
        (get-comp-type name (+ i u1) len)
        (if (char-is-dash-under c) u1 u2)))))

(define-private (get-composition-multiplier (comp-type uint))
  (if (is-eq comp-type u0) u1200 (if (is-eq comp-type u1) u1000 u900)))

(define-private (get-name-bucket (name (string-ascii 50)))
  (let ((len-bucket (if (<= (len name) u3) u0 (if (<= (len name) u5) u1 (if (<= (len name) u8) u2 u3))))
        (comp-bucket (get-comp-type name u0 (len name))))
    (+ (* len-bucket u10) comp-bucket)))

(define-private (get-recent-demand-helper (bucket uint) (epoch uint) (epochs-left uint))
  (if (is-eq epochs-left u0) u0
    (+ (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-epoch {b: bucket, e: epoch})))
       (get-recent-demand-helper bucket (if (> epoch u0) (- epoch u1) u0) (- epochs-left u1)))))

(define-private (get-recent-demand (bucket uint))
  (get-recent-demand-helper bucket (/ block-height EPOCH_LEN) EPOCH_WINDOW))

(define-private (search-price-history (target (string-ascii 48)) (max-index uint))
  (if (is-eq max-index u0) none
    (let ((entry (map-get? price-history (mod (- max-index u1) PH_CAP))))
      (match entry
        hist-data (if (is-eq (get name hist-data) target)
                     (some {price: (get price hist-data), block: (get block hist-data)}) none)
        none))))

;; Admin functions
(define-public (set-registry (new-registry principal))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err ERR_UNAUTHORIZED))
    (var-set registry (some new-registry))
    (ok true)))

(define-public (set-base-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err ERR_UNAUTHORIZED))
    (var-set base-price new-price)
    (ok true)))

;; Main pricing function
(define-read-only (get-name-price (name (string-ascii 50)))
  (let ((bucket (get-name-bucket name))
        (len-mult (get-length-multiplier (len name)))
        (comp-mult (get-composition-multiplier (get-comp-type name u0 (len name))))
        (recent (get-recent-demand bucket))
        (total (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-total bucket)))))
    (let ((demand-factor (if (is-eq total u0) SCALE
                           (/ (* (+ SCALE (* DEMAND_WEIGHT_1 recent)) SCALE)
                              (+ SCALE (* DEMAND_WEIGHT_2 total))))))
      (/ (* (* (* (var-get base-price) len-mult) comp-mult) demand-factor)
         (* (* SCALE SCALE) SCALE)))))

;; Record events
(define-public (on-register (name (string-ascii 50)))
  (let ((registry-addr (unwrap! (var-get registry) (err ERR_NO_REGISTRY))))
    (asserts! (is-eq tx-sender registry-addr) (err ERR_UNAUTHORIZED))
    (let ((bucket (get-name-bucket name))
          (current-epoch (/ block-height EPOCH_LEN))
          (price (get-name-price name))
          (hist-index (mod (var-get ph-index) PH_CAP)))
      (map-set bucket-total bucket
        {reg: (+ (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-total bucket))) u1),
         trans: (get trans (default-to {reg: u0, trans: u0} (map-get? bucket-total bucket)))})
      (map-set bucket-epoch {b: bucket, e: current-epoch}
        {reg: (+ (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-epoch {b: bucket, e: current-epoch}))) u1),
         trans: (get trans (default-to {reg: u0, trans: u0} (map-get? bucket-epoch {b: bucket, e: current-epoch})))})
      (map-set price-history hist-index
        {name: (unwrap-panic (as-max-len? name u48)), price: price, block: block-height, kind: u0})
      (var-set ph-index (+ (var-get ph-index) u1))
      (ok true))))

(define-public (on-transfer (name (string-ascii 50)))
  (let ((registry-addr (unwrap! (var-get registry) (err ERR_NO_REGISTRY))))
    (asserts! (is-eq tx-sender registry-addr) (err ERR_UNAUTHORIZED))
    (let ((bucket (get-name-bucket name))
          (current-epoch (/ block-height EPOCH_LEN))
          (hist-index (mod (var-get ph-index) PH_CAP)))
      (map-set bucket-total bucket
        {reg: (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-total bucket))),
         trans: (+ (get trans (default-to {reg: u0, trans: u0} (map-get? bucket-total bucket))) u1)})
      (map-set bucket-epoch {b: bucket, e: current-epoch}
        {reg: (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-epoch {b: bucket, e: current-epoch}))),
         trans: (+ (get trans (default-to {reg: u0, trans: u0} (map-get? bucket-epoch {b: bucket, e: current-epoch}))) u1)})
      (map-set price-history hist-index
        {name: (unwrap-panic (as-max-len? name u48)), price: u0, block: block-height, kind: u1})
      (var-set ph-index (+ (var-get ph-index) u1))
      (ok true))))

;; Analytics
(define-read-only (get-bucket-stats (name (string-ascii 50)))
  (let ((bucket (get-name-bucket name))
        (recent (get-recent-demand bucket))
        (total (get reg (default-to {reg: u0, trans: u0} (map-get? bucket-total bucket)))))
    {bucket: bucket, recent: recent, total: total}))

(define-read-only (get-last-price (name (string-ascii 50)))
  (search-price-history (unwrap-panic (as-max-len? name u48)) (var-get ph-index)))

(define-read-only (get-current-base-price)
  (var-get base-price))
