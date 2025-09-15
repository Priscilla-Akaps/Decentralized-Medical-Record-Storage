;; Time Vault System
;; Advanced time-based access control with staged releases and conditional unlocking

(define-constant CONTRACT-OWNER tx-sender)

;; Error constants  
(define-constant ERR-NOT-AUTHORIZED u400)
(define-constant ERR-VAULT-NOT-FOUND u401)
(define-constant ERR-VAULT-EXISTS u402)
(define-constant ERR-INVALID-TIME u403)
(define-constant ERR-VAULT-LOCKED u404)
(define-constant ERR-STAGE-NOT-FOUND u405)
(define-constant ERR-STAGE-LOCKED u406)
(define-constant ERR-MAX-STAGES-EXCEEDED u407)
(define-constant ERR-INVALID-STAGE u408)
(define-constant ERR-CONDITION-NOT-MET u409)

;; Constants
(define-constant MAX-STAGES u10)
(define-constant MIN-UNLOCK-TIME u3600) ;; 1 hour minimum
(define-constant MAX-DESCRIPTION-LENGTH u200)

;; Data variables
(define-data-var total-vaults uint u0)
(define-data-var total-stages uint u0)

;; Time vaults with progressive release stages
(define-map time-vaults uint
    {
        owner: principal,
        name: (string-ascii 100),
        description: (string-ascii 200),
        created-at: uint,
        total-stages: uint,
        is-active: bool,
        emergency-key: (optional (string-ascii 64)),
        access-conditions: (string-ascii 100)
    }
)

;; Staged release system
(define-map vault-stages {vault-id: uint, stage-number: uint}
    {
        stage-name: (string-ascii 50),
        content-hash: (string-ascii 64),
        unlock-time: uint,
        unlock-condition: (string-ascii 50),
        condition-value: uint,
        is-unlocked: bool,
        unlocked-at: (optional uint),
        authorized-users: (list 5 principal),
        stage-type: (string-ascii 20)
    }
)

;; User vault access permissions
(define-map vault-permissions {vault-id: uint, user: principal}
    {
        access-level: uint,
        granted-at: uint,
        expires-at: (optional uint),
        granted-by: principal,
        can-unlock-stages: bool
    }
)

;; Access audit log
(define-map access-logs {vault-id: uint, access-id: uint}
    {
        accessor: principal,
        accessed-at: uint,
        stage-accessed: uint,
        access-type: (string-ascii 20),
        success: bool
    }
)

;; Time-based conditions tracker
(define-map condition-trackers {vault-id: uint, condition-type: (string-ascii 50)}
    {
        current-value: uint,
        last-updated: uint,
        threshold: uint,
        is-met: bool
    }
)

;; User vault list for quick lookup
(define-map user-vaults principal (list 20 uint))

;; Data tracking
(define-data-var next-access-id uint u1)

;; Public Functions

;; Create a new time vault
(define-public (create-time-vault 
    (name (string-ascii 100)) 
    (description (string-ascii 200))
    (emergency-key (optional (string-ascii 64)))
    (access-conditions (string-ascii 100)))
    (let
        (
            (vault-id (+ (var-get total-vaults) u1))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (> (len name) u0) (err ERR-INVALID-TIME))
        
        ;; Create vault
        (map-set time-vaults vault-id
            {
                owner: tx-sender,
                name: name,
                description: description,
                created-at: current-time,
                total-stages: u0,
                is-active: true,
                emergency-key: emergency-key,
                access-conditions: access-conditions
            }
        )
        
        ;; Add to user's vault list
        (let
            (
                (user-vault-list (default-to (list) (map-get? user-vaults tx-sender)))
            )
            (map-set user-vaults tx-sender 
                (unwrap! (as-max-len? (append user-vault-list vault-id) u20) (err ERR-MAX-STAGES-EXCEEDED))
            )
        )
        
        (var-set total-vaults vault-id)
        (ok vault-id)
    )
)

;; Add a release stage to vault
(define-public (add-release-stage
    (vault-id uint)
    (stage-name (string-ascii 50))
    (content-hash (string-ascii 64))
    (unlock-time uint)
    (unlock-condition (string-ascii 50))
    (condition-value uint)
    (authorized-users (list 5 principal))
    (stage-type (string-ascii 20)))
    (let
        (
            (vault (unwrap! (map-get? time-vaults vault-id) (err ERR-VAULT-NOT-FOUND)))
            (stage-number (+ (get total-stages vault) u1))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq tx-sender (get owner vault)) (err ERR-NOT-AUTHORIZED))
        (asserts! (get is-active vault) (err ERR-VAULT-LOCKED))
        (asserts! (< (get total-stages vault) MAX-STAGES) (err ERR-MAX-STAGES-EXCEEDED))
        (asserts! (> unlock-time (+ current-time MIN-UNLOCK-TIME)) (err ERR-INVALID-TIME))
        
        ;; Create stage
        (map-set vault-stages {vault-id: vault-id, stage-number: stage-number}
            {
                stage-name: stage-name,
                content-hash: content-hash,
                unlock-time: unlock-time,
                unlock-condition: unlock-condition,
                condition-value: condition-value,
                is-unlocked: false,
                unlocked-at: none,
                authorized-users: authorized-users,
                stage-type: stage-type
            }
        )
        
        ;; Update vault total stages
        (map-set time-vaults vault-id
            (merge vault {total-stages: stage-number})
        )
        
        ;; Initialize condition tracker if needed
        (if (> (len unlock-condition) u0)
            (map-set condition-trackers {vault-id: vault-id, condition-type: unlock-condition}
                {
                    current-value: u0,
                    last-updated: current-time,
                    threshold: condition-value,
                    is-met: false
                }
            )
            true
        )
        
        (var-set total-stages (+ (var-get total-stages) u1))
        (ok stage-number)
    )
)

;; Attempt to unlock a stage
(define-public (unlock-stage (vault-id uint) (stage-number uint))
    (let
        (
            (vault (unwrap! (map-get? time-vaults vault-id) (err ERR-VAULT-NOT-FOUND)))
            (stage (unwrap! (map-get? vault-stages {vault-id: vault-id, stage-number: stage-number}) (err ERR-STAGE-NOT-FOUND)))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
            (access-id (var-get next-access-id))
        )
        (asserts! (get is-active vault) (err ERR-VAULT-LOCKED))
        (asserts! (not (get is-unlocked stage)) (err ERR-STAGE-LOCKED))
        
        ;; Check authorization
        (asserts! 
            (or 
                (is-eq tx-sender (get owner vault))
                (is-authorized-user vault-id tx-sender)
                (is-stage-authorized vault-id stage-number tx-sender)
            ) 
            (err ERR-NOT-AUTHORIZED)
        )
        
        ;; Check time condition
        (asserts! (>= current-time (get unlock-time stage)) (err ERR-CONDITION-NOT-MET))
        
        ;; Check additional conditions if any
        (asserts! (check-unlock-conditions vault-id stage) (err ERR-CONDITION-NOT-MET))
        
        ;; Unlock stage
        (map-set vault-stages {vault-id: vault-id, stage-number: stage-number}
            (merge stage 
                {
                    is-unlocked: true,
                    unlocked-at: (some current-time)
                }
            )
        )
        
        ;; Log access
        (map-set access-logs {vault-id: vault-id, access-id: access-id}
            {
                accessor: tx-sender,
                accessed-at: current-time,
                stage-accessed: stage-number,
                access-type: "unlock",
                success: true
            }
        )
        
        (var-set next-access-id (+ access-id u1))
        (ok true)
    )
)

;; Grant vault access to a user
(define-public (grant-vault-access 
    (vault-id uint) 
    (user principal) 
    (access-level uint) 
    (expires-at (optional uint))
    (can-unlock-stages bool))
    (let
        (
            (vault (unwrap! (map-get? time-vaults vault-id) (err ERR-VAULT-NOT-FOUND)))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq tx-sender (get owner vault)) (err ERR-NOT-AUTHORIZED))
        (asserts! (get is-active vault) (err ERR-VAULT-LOCKED))
        
        (map-set vault-permissions {vault-id: vault-id, user: user}
            {
                access-level: access-level,
                granted-at: current-time,
                expires-at: expires-at,
                granted-by: tx-sender,
                can-unlock-stages: can-unlock-stages
            }
        )
        
        (ok true)
    )
)

;; Emergency unlock with emergency key
(define-public (emergency-unlock (vault-id uint) (emergency-key (string-ascii 64)))
    (let
        (
            (vault (unwrap! (map-get? time-vaults vault-id) (err ERR-VAULT-NOT-FOUND)))
            (stored-key (get emergency-key vault))
        )
        (asserts! (is-some stored-key) (err ERR-NOT-AUTHORIZED))
        (asserts! (is-eq emergency-key (unwrap-panic stored-key)) (err ERR-NOT-AUTHORIZED))
        
        ;; Unlock all stages
        (unwrap! (unlock-all-stages vault-id) (err u999))
        
        (ok true)
    )
)

;; Update condition value for conditional unlocking
(define-public (update-condition-value 
    (vault-id uint) 
    (condition-type (string-ascii 50)) 
    (new-value uint))
    (let
        (
            (vault (unwrap! (map-get? time-vaults vault-id) (err ERR-VAULT-NOT-FOUND)))
            (tracker (unwrap! (map-get? condition-trackers {vault-id: vault-id, condition-type: condition-type}) (err ERR-STAGE-NOT-FOUND)))
            (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        )
        (asserts! (is-eq tx-sender (get owner vault)) (err ERR-NOT-AUTHORIZED))
        
        (let
            (
                (threshold-met (>= new-value (get threshold tracker)))
            )
            (map-set condition-trackers {vault-id: vault-id, condition-type: condition-type}
                (merge tracker 
                    {
                        current-value: new-value,
                        last-updated: current-time,
                        is-met: threshold-met
                    }
                )
            )
            
            (ok threshold-met)
        )
    )
)

;; Read-only functions

(define-read-only (get-time-vault (vault-id uint))
    (map-get? time-vaults vault-id)
)

(define-read-only (get-vault-stage (vault-id uint) (stage-number uint))
    (map-get? vault-stages {vault-id: vault-id, stage-number: stage-number})
)

(define-read-only (get-vault-permissions (vault-id uint) (user principal))
    (map-get? vault-permissions {vault-id: vault-id, user: user})
)

(define-read-only (get-user-vaults (user principal))
    (default-to (list) (map-get? user-vaults user))
)

(define-read-only (get-condition-tracker (vault-id uint) (condition-type (string-ascii 50)))
    (map-get? condition-trackers {vault-id: vault-id, condition-type: condition-type})
)

(define-read-only (get-access-log (vault-id uint) (access-id uint))
    (map-get? access-logs {vault-id: vault-id, access-id: access-id})
)

(define-read-only (get-system-stats)
    {
        total-vaults: (var-get total-vaults),
        total-stages: (var-get total-stages)
    }
)

(define-read-only (is-stage-unlockable (vault-id uint) (stage-number uint))
    (match (map-get? vault-stages {vault-id: vault-id, stage-number: stage-number})
        stage
        (let
            (
                (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
                (time-condition-met (>= current-time (get unlock-time stage)))
                (not-already-unlocked (not (get is-unlocked stage)))
                (conditions-met (check-unlock-conditions vault-id stage))
            )
            (and time-condition-met (and not-already-unlocked conditions-met))
        )
        false
    )
)

;; Private functions

(define-private (is-authorized-user (vault-id uint) (user principal))
    (match (map-get? vault-permissions {vault-id: vault-id, user: user})
        permissions
        (let
            (
                (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
            )
            (match (get expires-at permissions)
                expiry-time (< current-time expiry-time)
                true
            )
        )
        false
    )
)

(define-private (is-stage-authorized (vault-id uint) (stage-number uint) (user principal))
    (match (map-get? vault-stages {vault-id: vault-id, stage-number: stage-number})
        stage
        (is-some (index-of (get authorized-users stage) user))
        false
    )
)

(define-private (check-unlock-conditions (vault-id uint) (stage (tuple (stage-name (string-ascii 50)) (content-hash (string-ascii 64)) (unlock-time uint) (unlock-condition (string-ascii 50)) (condition-value uint) (is-unlocked bool) (unlocked-at (optional uint)) (authorized-users (list 5 principal)) (stage-type (string-ascii 20)))))
    (let
        (
            (condition-type (get unlock-condition stage))
        )
        (if (is-eq (len condition-type) u0)
            true
            (match (map-get? condition-trackers {vault-id: vault-id, condition-type: condition-type})
                tracker (get is-met tracker)
                false
            )
        )
    )
)

(define-private (unlock-all-stages (vault-id uint))
    (let
        (
            (vault (unwrap! (map-get? time-vaults vault-id) (err ERR-VAULT-NOT-FOUND)))
            (total-stages (get total-stages vault))
        )
        (unlock-stages-recursive vault-id u1 total-stages)
    )
)

(define-private (unlock-stages-recursive (vault-id uint) (current-stage uint) (total-stages uint))
    (if (<= current-stage total-stages)
        (begin
            (match (map-get? vault-stages {vault-id: vault-id, stage-number: current-stage})
                stage
                (map-set vault-stages {vault-id: vault-id, stage-number: current-stage}
                    (merge stage 
                        {
                            is-unlocked: true,
                            unlocked-at: (some (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
                        }
                    )
                )
                true
            )
            (unlock-stages-recursive vault-id (+ current-stage u1) total-stages)
        )
        (ok true)
    )
)
