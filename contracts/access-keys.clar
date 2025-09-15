;; Digital Access Keys - Smart Property Access Management
;; Issues revocable, time-bound NFT tokens as digital keys for property access

;; Define NFT
(define-non-fungible-token access-key uint)

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u600))
(define-constant ERR-TOKEN-NOT-FOUND (err u601))
(define-constant ERR-TRANSFER-DISABLED (err u602))
(define-constant ERR-KEY-EXPIRED (err u603))
(define-constant ERR-KEY-REVOKED (err u604))
(define-constant ERR-INVALID-DURATION (err u605))

;; Data storage
(define-map access-keys
    uint
    {
        owner: principal,
        property: principal,
        expires-at: uint,
        active: bool,
        issued-by: principal,
        issued-at: uint
    }
)

(define-map property-key-count principal uint)
(define-map tenant-active-keys { tenant: principal, property: principal } uint)

;; Contract variables
(define-data-var next-token-id uint u1)
(define-data-var contract-owner principal tx-sender)

;; SIP-009 Implementation
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    ERR-TRANSFER-DISABLED)

(define-read-only (get-owner (token-id uint))
    (ok (get owner (map-get? access-keys token-id))))

(define-read-only (get-last-token-id)
    (ok (- (var-get next-token-id) u1)))

(define-read-only (get-token-uri (token-id uint))
    (ok (some "https://access-keys.rent/metadata/{id}")))

;; Core Functions

;; Mint new access key for tenant
(define-public (mint-access-key (tenant principal) (property principal) (duration-blocks uint))
    (let (
        (token-id (var-get next-token-id))
        (expires-at (+ stacks-block-height duration-blocks))
        (current-count (default-to u0 (map-get? property-key-count property)))
    )
        (begin
            (asserts! (> duration-blocks u0) ERR-INVALID-DURATION)
            (asserts! (<= duration-blocks u52560) ERR-INVALID-DURATION)
            
            ;; Mint NFT
            (try! (nft-mint? access-key token-id tenant))
            
            ;; Store key details
            (map-set access-keys token-id {
                owner: tenant,
                property: property,
                expires-at: expires-at,
                active: true,
                issued-by: tx-sender,
                issued-at: stacks-block-height
            })
            
            ;; Update counters
            (map-set property-key-count property (+ current-count u1))
            (map-set tenant-active-keys { tenant: tenant, property: property } token-id)
            (var-set next-token-id (+ token-id u1))
            
            (ok token-id))))

;; Revoke access key (landlord only)
(define-public (revoke-access-key (token-id uint))
    (let (
        (key-data (unwrap! (map-get? access-keys token-id) ERR-TOKEN-NOT-FOUND))
        (issued-by (get issued-by key-data))
    )
        (begin
            (asserts! (is-eq tx-sender issued-by) ERR-NOT-AUTHORIZED)
            (map-set access-keys token-id 
                (merge key-data { active: false }))
            (ok true))))

;; Extend key expiration (landlord only)
(define-public (extend-access-key (token-id uint) (additional-blocks uint))
    (let (
        (key-data (unwrap! (map-get? access-keys token-id) ERR-TOKEN-NOT-FOUND))
        (issued-by (get issued-by key-data))
        (current-expires (get expires-at key-data))
    )
        (begin
            (asserts! (is-eq tx-sender issued-by) ERR-NOT-AUTHORIZED)
            (asserts! (get active key-data) ERR-KEY-REVOKED)
            (asserts! (> additional-blocks u0) ERR-INVALID-DURATION)
            
            (map-set access-keys token-id 
                (merge key-data { 
                    expires-at: (+ current-expires additional-blocks) 
                }))
            (ok (+ current-expires additional-blocks)))))

;; Read-only functions

;; Check if tenant has valid key for property
(define-read-only (has-valid-access-key (tenant principal) (property principal))
    (match (map-get? tenant-active-keys { tenant: tenant, property: property })
        token-id 
            (match (map-get? access-keys token-id)
                key-data 
                    (and 
                        (get active key-data)
                        (> (get expires-at key-data) stacks-block-height)
                        (is-eq (get property key-data) property)
                        (is-eq (get owner key-data) tenant))
                false)
        false))

;; Get key details
(define-read-only (get-access-key-details (token-id uint))
    (map-get? access-keys token-id))

;; Get active key for tenant-property pair
(define-read-only (get-tenant-property-key (tenant principal) (property principal))
    (map-get? tenant-active-keys { tenant: tenant, property: property }))

;; Check if key is currently valid (not expired/revoked)
(define-read-only (is-key-valid (token-id uint))
    (match (map-get? access-keys token-id)
        key-data 
            (and 
                (get active key-data)
                (> (get expires-at key-data) stacks-block-height))
        false))

;; Get property key statistics
(define-read-only (get-property-key-stats (property principal))
    (some {
        total-keys-issued: (default-to u0 (map-get? property-key-count property))
    }))

;; Verify access for external systems (IoT locks, etc.)
(define-read-only (verify-property-access (tenant principal) (property principal))
    (let (
        (has-valid-key (has-valid-access-key tenant property))
    )
        {
            access-granted: has-valid-key,
            verified-at: stacks-block-height,
            tenant: tenant,
            property: property
        }))

;; Admin functions

;; Update contract owner (current owner only)
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)))

;; Emergency pause (future implementation)
(define-read-only (get-contract-info)
    {
        total-keys-minted: (- (var-get next-token-id) u1),
        contract-owner: (var-get contract-owner)
    })
