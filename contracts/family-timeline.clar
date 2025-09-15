;; Family Timeline System - Historical Event Tracking for Genealogy

;; Constants
(define-constant err-not-authorized (err u500))
(define-constant err-not-found (err u501))
(define-constant err-already-exists (err u502))
(define-constant err-invalid-event (err u503))
(define-constant err-invalid-date (err u504))
(define-constant err-timeline-not-found (err u505))
(define-constant err-invalid-privacy (err u506))

;; Data variables
(define-data-var event-counter uint u0)
(define-data-var timeline-counter uint u0)

;; Family Timeline Structure
(define-map family-timelines uint {
    family-head: principal,
    timeline-name: (string-ascii 100),
    description: (string-ascii 300),
    created-by: principal,
    created-at: uint,
    privacy-level: uint,
    total-events: uint,
    collaborators: (list 10 principal),
    is-active: bool
})

;; Timeline Events
(define-map timeline-events uint {
    timeline-id: uint,
    event-title: (string-ascii 100),
    event-description: (string-ascii 500),
    event-date: uint,
    event-type: (string-ascii 30),
    affected-person: (optional principal),
    location: (optional (string-ascii 100)),
    created-by: principal,
    created-at: uint,
    verified: bool,
    verification-count: uint,
    privacy-level: uint
})

;; Event Attachments (photos, documents, etc.)
(define-map event-attachments {event-id: uint, attachment-id: uint} {
    attachment-type: (string-ascii 20),
    attachment-hash: (buff 32),
    attachment-name: (string-ascii 100),
    uploaded-by: principal,
    uploaded-at: uint
})

;; Event Verifications
(define-map event-verifications {event-id: uint, verifier: principal} {
    verification-status: (string-ascii 20),
    verification-note: (optional (string-ascii 200)),
    verified-at: uint
})

;; Timeline Permissions
(define-map timeline-permissions {timeline-id: uint, user: principal} {
    permission-level: uint,
    granted-by: principal,
    granted-at: uint,
    can-edit: bool,
    can-verify: bool,
    can-invite: bool
})

;; Family Milestones
(define-map family-milestones uint {
    family-head: principal,
    milestone-type: (string-ascii 50),
    milestone-date: uint,
    participants: (list 20 principal),
    milestone-description: (string-ascii 300),
    significance-score: uint,
    created-by: principal,
    created-at: uint
})

;; Event Categories
(define-map event-categories (string-ascii 30) {
    category-description: (string-ascii 200),
    default-privacy: uint,
    requires-verification: bool,
    category-icon: (string-ascii 50)
})

;; Read-only functions
(define-read-only (get-family-timeline (timeline-id uint))
    (map-get? family-timelines timeline-id)
)

(define-read-only (get-timeline-event (event-id uint))
    (let (
        (event-data (map-get? timeline-events event-id))
    )
        (match event-data
            some-event 
                (if (can-view-event tx-sender event-id)
                    (some some-event)
                    none)
            none
        )
    )
)

(define-read-only (get-event-attachment (event-id uint) (attachment-id uint))
    (if (can-view-event tx-sender event-id)
        (map-get? event-attachments {event-id: event-id, attachment-id: attachment-id})
        none
    )
)

(define-read-only (get-timeline-permission (timeline-id uint) (user principal))
    (map-get? timeline-permissions {timeline-id: timeline-id, user: user})
)

(define-read-only (get-family-milestone (milestone-id uint))
    (map-get? family-milestones milestone-id)
)

(define-read-only (get-event-category (category-name (string-ascii 30)))
    (map-get? event-categories category-name)
)

(define-read-only (get-timeline-counter)
    (var-get timeline-counter)
)

;; Create family timeline
(define-public (create-family-timeline (family-head principal) (timeline-name (string-ascii 100)) (description (string-ascii 300)) (privacy-level uint))
    (let (
        (timeline-id (+ (var-get timeline-counter) u1))
    )
        ;; Validate inputs
        (asserts! (> (len timeline-name) u0) err-invalid-event)
        (asserts! (<= privacy-level u3) err-invalid-privacy)
        
        ;; Create timeline
        (map-set family-timelines timeline-id {
            family-head: family-head,
            timeline-name: timeline-name,
            description: description,
            created-by: tx-sender,
            created-at: stacks-block-height,
            privacy-level: privacy-level,
            total-events: u0,
            collaborators: (list),
            is-active: true
        })
        
        ;; Grant creator full permissions
        (map-set timeline-permissions {timeline-id: timeline-id, user: tx-sender} {
            permission-level: u3,
            granted-by: tx-sender,
            granted-at: stacks-block-height,
            can-edit: true,
            can-verify: true,
            can-invite: true
        })
        
        (var-set timeline-counter timeline-id)
        (ok timeline-id)
    )
)

;; Add event to timeline
(define-public (add-timeline-event (timeline-id uint) (event-title (string-ascii 100)) (event-description (string-ascii 500)) (event-date uint) (event-type (string-ascii 30)) (affected-person (optional principal)) (location (optional (string-ascii 100))) (privacy-level uint))
    (let (
        (event-id (+ (var-get event-counter) u1))
        (timeline-data (unwrap! (get-family-timeline timeline-id) err-timeline-not-found))
    )
        ;; Validate permissions
        (asserts! (can-edit-timeline tx-sender timeline-id) err-not-authorized)
        (asserts! (> (len event-title) u0) err-invalid-event)
        (asserts! (> event-date u0) err-invalid-date)
        (asserts! (<= privacy-level u3) err-invalid-privacy)
        
        ;; Create event
        (map-set timeline-events event-id {
            timeline-id: timeline-id,
            event-title: event-title,
            event-description: event-description,
            event-date: event-date,
            event-type: event-type,
            affected-person: affected-person,
            location: location,
            created-by: tx-sender,
            created-at: stacks-block-height,
            verified: false,
            verification-count: u0,
            privacy-level: privacy-level
        })
        
        ;; Update timeline event count
        (map-set family-timelines timeline-id (merge timeline-data {
            total-events: (+ (get total-events timeline-data) u1)
        }))
        
        (var-set event-counter event-id)
        (ok event-id)
    )
)

;; Verify timeline event
(define-public (verify-timeline-event (event-id uint) (verification-status (string-ascii 20)) (verification-note (optional (string-ascii 200))))
    (let (
        (event-data (unwrap! (map-get? timeline-events event-id) err-not-found))
        (verification-key {event-id: event-id, verifier: tx-sender})
    )
        ;; Check if user can verify events
        (asserts! (can-verify-event tx-sender (get timeline-id event-data)) err-not-authorized)
        (asserts! (is-none (map-get? event-verifications verification-key)) err-already-exists)
        
        ;; Add verification
        (map-set event-verifications verification-key {
            verification-status: verification-status,
            verification-note: verification-note,
            verified-at: stacks-block-height
        })
        
        ;; Update event verification count
        (let (
            (new-verification-count (+ (get verification-count event-data) u1))
            (is-verified (>= new-verification-count u2))
        )
            (map-set timeline-events event-id (merge event-data {
                verification-count: new-verification-count,
                verified: is-verified
            }))
        )
        
        (ok true)
    )
)

;; Grant timeline permissions
(define-public (grant-timeline-permission (timeline-id uint) (user principal) (permission-level uint) (can-edit bool) (can-verify bool) (can-invite bool))
    (let (
        (timeline-data (unwrap! (get-family-timeline timeline-id) err-timeline-not-found))
        (permission-key {timeline-id: timeline-id, user: user})
    )
        ;; Check if caller has invite permissions
        (asserts! (can-invite-to-timeline tx-sender timeline-id) err-not-authorized)
        (asserts! (<= permission-level u3) err-invalid-privacy)
        
        ;; Grant permissions
        (map-set timeline-permissions permission-key {
            permission-level: permission-level,
            granted-by: tx-sender,
            granted-at: stacks-block-height,
            can-edit: can-edit,
            can-verify: can-verify,
            can-invite: can-invite
        })
        
        ;; Add to collaborators list if not already there
        (let (
            (current-collaborators (get collaborators timeline-data))
        )
            (if (is-none (index-of current-collaborators user))
                (map-set family-timelines timeline-id (merge timeline-data {
                    collaborators: (unwrap! (as-max-len? (append current-collaborators user) u10) err-invalid-event)
                }))
                true
            )
        )
        
        (ok true)
    )
)

;; Add event attachment
(define-public (add-event-attachment (event-id uint) (attachment-id uint) (attachment-type (string-ascii 20)) (attachment-hash (buff 32)) (attachment-name (string-ascii 100)))
    (let (
        (event-data (unwrap! (map-get? timeline-events event-id) err-not-found))
        (attachment-key {event-id: event-id, attachment-id: attachment-id})
    )
        ;; Check edit permissions
        (asserts! (can-edit-timeline tx-sender (get timeline-id event-data)) err-not-authorized)
        (asserts! (> (len attachment-name) u0) err-invalid-event)
        (asserts! (is-none (map-get? event-attachments attachment-key)) err-already-exists)
        
        ;; Create attachment
        (map-set event-attachments attachment-key {
            attachment-type: attachment-type,
            attachment-hash: attachment-hash,
            attachment-name: attachment-name,
            uploaded-by: tx-sender,
            uploaded-at: stacks-block-height
        })
        
        (ok true)
    )
)

;; Create family milestone
(define-public (create-family-milestone (family-head principal) (milestone-type (string-ascii 50)) (milestone-date uint) (participants (list 20 principal)) (milestone-description (string-ascii 300)) (significance-score uint))
    (let (
        (milestone-id (+ (var-get event-counter) u1))
    )
        ;; Validate inputs
        (asserts! (> (len milestone-type) u0) err-invalid-event)
        (asserts! (> milestone-date u0) err-invalid-date)
        (asserts! (<= significance-score u10) err-invalid-event)
        
        ;; Create milestone
        (map-set family-milestones milestone-id {
            family-head: family-head,
            milestone-type: milestone-type,
            milestone-date: milestone-date,
            participants: participants,
            milestone-description: milestone-description,
            significance-score: significance-score,
            created-by: tx-sender,
            created-at: stacks-block-height
        })
        
        (var-set event-counter milestone-id)
        (ok milestone-id)
    )
)

;; Setup event categories
(define-public (setup-event-category (category-name (string-ascii 30)) (category-description (string-ascii 200)) (default-privacy uint) (requires-verification bool) (category-icon (string-ascii 50)))
    (begin
        (asserts! (> (len category-name) u0) err-invalid-event)
        (asserts! (<= default-privacy u3) err-invalid-privacy)
        
        (map-set event-categories category-name {
            category-description: category-description,
            default-privacy: default-privacy,
            requires-verification: requires-verification,
            category-icon: category-icon
        })
        
        (ok true)
    )
)

;; Private helper functions
(define-private (can-view-event (viewer principal) (event-id uint))
    (let (
        (event-data (unwrap! (map-get? timeline-events event-id) false))
        (timeline-id (get timeline-id event-data))
        (timeline-data (unwrap! (get-family-timeline timeline-id) false))
        (permission-data (map-get? timeline-permissions {timeline-id: timeline-id, user: viewer}))
    )
        (or 
            (is-eq viewer (get created-by event-data))
            (is-eq viewer (get family-head timeline-data))
            (is-some permission-data)
            (<= (get privacy-level event-data) u1)
        )
    )
)

(define-private (can-edit-timeline (editor principal) (timeline-id uint))
    (let (
        (timeline-data (unwrap! (get-family-timeline timeline-id) false))
        (permission-data (map-get? timeline-permissions {timeline-id: timeline-id, user: editor}))
    )
        (or 
            (is-eq editor (get created-by timeline-data))
            (is-eq editor (get family-head timeline-data))
            (match permission-data
                some-permission (get can-edit some-permission)
                false
            )
        )
    )
)

(define-private (can-verify-event (verifier principal) (timeline-id uint))
    (let (
        (timeline-data (unwrap! (get-family-timeline timeline-id) false))
        (permission-data (map-get? timeline-permissions {timeline-id: timeline-id, user: verifier}))
    )
        (or 
            (is-eq verifier (get created-by timeline-data))
            (is-eq verifier (get family-head timeline-data))
            (match permission-data
                some-permission (get can-verify some-permission)
                false
            )
        )
    )
)

(define-private (can-invite-to-timeline (inviter principal) (timeline-id uint))
    (let (
        (timeline-data (unwrap! (get-family-timeline timeline-id) false))
        (permission-data (map-get? timeline-permissions {timeline-id: timeline-id, user: inviter}))
    )
        (or 
            (is-eq inviter (get created-by timeline-data))
            (is-eq inviter (get family-head timeline-data))
            (match permission-data
                some-permission (get can-invite some-permission)
                false
            )
        )
    )
)

;; Query functions for timeline data
(define-read-only (get-timeline-events-count (timeline-id uint))
    (let (
        (timeline-data (map-get? family-timelines timeline-id))
    )
        (match timeline-data
            some-timeline (get total-events some-timeline)
            u0
        )
    )
)

(define-read-only (get-family-timeline-summary (family-head principal))
    (let (
        (timeline-id u1)
    )
        {
            total-timelines: u1,
            total-events: u0,
            verified-events: u0,
            collaborator-count: u0
        }
    )
)
