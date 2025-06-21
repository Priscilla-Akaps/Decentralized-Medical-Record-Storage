;; Medical Records Storage Contract

;; Data Maps
(define-map medical-records 
    { patient: principal }
    {
        diagnosis: (string-utf8 500),
        date: uint,
        doctor: principal,
        hospital: (string-utf8 100)
    }
)

(define-map access-permissions
    { patient: principal, provider: principal }
    { has-access: bool }
)

;; Public Functions
(define-public (add-medical-record (diagnosis (string-utf8 500)) (hospital (string-utf8 100)))
    (ok (map-set medical-records
        { patient: tx-sender }
        {
            diagnosis: diagnosis,
            date: stacks-block-height,
            doctor: tx-sender,
            hospital: hospital
        }
    ))
)

(define-public (grant-access (provider principal))
    (ok (map-set access-permissions
        { patient: tx-sender, provider: provider }
        { has-access: true }
    ))
)

(define-public (revoke-access (provider principal))
    (ok (map-set access-permissions
        { patient: tx-sender, provider: provider }
        { has-access: false }
    ))
)

;; Read Only Functions
(define-read-only (get-medical-record (patient principal))
    (let (
        (caller-has-access (default-to { has-access: false }
            (map-get? access-permissions { patient: patient, provider: tx-sender })))
    )
    (if (or 
        (is-eq tx-sender patient)
        (get has-access caller-has-access)
    )
        (ok (map-get? medical-records { patient: patient }))
        (err u403)
    ))
)


;; Add to data maps
;; Emergency Contacts (existing)
(define-map emergency-contacts
    { patient: principal }
    { contact: principal }
)

;; Add public function
(define-public (set-emergency-contact (contact principal))
    (ok (map-set emergency-contacts
        { patient: tx-sender }
        { contact: contact }
    ))
)


;; Add to data maps
;; Medical History
(define-map medical-history
    { patient: principal, record-id: uint }
    {
        diagnosis: (string-utf8 500),
        date: uint,
        doctor: principal,
        hospital: (string-utf8 100)
    }
)

(define-data-var record-counter uint u0)

;; Add public function
(define-public (add-history-record (diagnosis (string-utf8 500)) (hospital (string-utf8 100)))
    (let
        ((new-id (+ (var-get record-counter) u1)))
        (var-set record-counter new-id)
        (ok (map-set medical-history
            { patient: tx-sender, record-id: new-id }
            {
                diagnosis: diagnosis,
                date: stacks-block-height,
                doctor: tx-sender,
                hospital: hospital
            }
        ))
    )
)




;; Add to data maps
;; Prescriptions
(define-map prescriptions
    { patient: principal, prescription-id: uint }
    {
        medication: (string-utf8 100),
        dosage: (string-utf8 50),
        doctor: principal,
        date: uint,
        valid-until: uint
    }
)

(define-data-var prescription-counter uint u0)

;; Add public function
(define-public (add-prescription (medication (string-utf8 100)) (dosage (string-utf8 50)) (valid-days uint))
    (let
        ((new-id (+ (var-get prescription-counter) u1)))
        (var-set prescription-counter new-id)
        (ok (map-set prescriptions
            { patient: tx-sender, prescription-id: new-id }
            {
                medication: medication,
                dosage: dosage,
                doctor: tx-sender,
                date: stacks-block-height,
                valid-until: (+ stacks-block-height (* valid-days u144))
            }
        ))
    )
)




;; Add to data maps
;; Test Results
(define-map test-results
    { patient: principal, test-id: uint }
    {
        test-name: (string-utf8 100),
        result: (string-utf8 500),
        date: uint,
        lab: (string-utf8 100)
    }
)

(define-data-var test-counter uint u0)

;; Add public function
(define-public (add-test-result (test-name (string-utf8 100)) (result (string-utf8 500)) (lab (string-utf8 100)))
    (let
        ((new-id (+ (var-get test-counter) u1)))
        (var-set test-counter new-id)
        (ok (map-set test-results
            { patient: tx-sender, test-id: new-id }
            {
                test-name: test-name,
                result: result,
                date: stacks-block-height,
                lab: lab
            }
        ))
    )
)



;; Add to data maps
;; Insurance Info
(define-map insurance-info
    { patient: principal }
    {
        provider: (string-utf8 100),
        policy-number: (string-utf8 50),
        valid-until: uint
    }
)

;; Add public function
(define-public (update-insurance (provider (string-utf8 100)) (policy-number (string-utf8 50)) (valid-days uint))
    (ok (map-set insurance-info
        { patient: tx-sender }
        {
            provider: provider,
            policy-number: policy-number,
            valid-until: (+ stacks-block-height (* valid-days u144))
        }
    ))
)




;; Add to data maps
;; Patient Allergies & Conditions
(define-map patient-allergies
    { patient: principal }
    {
        allergies: (list 20 (string-utf8 50)),
        conditions: (list 20 (string-utf8 100))
    }
)

;; Add public function
(define-public (update-allergies-conditions (allergies (list 20 (string-utf8 50))) (conditions (list 20 (string-utf8 100))))
    (ok (map-set patient-allergies
        { patient: tx-sender }
        {
            allergies: allergies,
            conditions: conditions
        }
    ))
)

;;    Map to store appointments with a unique appointment id.
(define-map appointments
    { patient: principal, appointment-id: uint }
    {
        doctor: principal,
        appointment-date: uint,
        hospital: (string-utf8 100),
        notes: (string-utf8 250)
    }
)

(define-data-var appointment-counter uint u0)

(define-public (schedule-appointment (doctor principal) (appointment-date uint) (hospital (string-utf8 100)) (notes (string-utf8 250)))
    (let
        ((new-id (+ (var-get appointment-counter) u1)))
        (var-set appointment-counter new-id)
        (ok (map-set appointments
            { patient: tx-sender, appointment-id: new-id }
            {
                doctor: doctor,
                appointment-date: appointment-date,
                hospital: hospital,
                notes: notes
            }
        ))
    )
)

;;    Allows providers (or patients) to add notes to a history record.
(define-map record-notes
    { patient: principal, record-id: uint }
    {
        note: (string-utf8 500),
        date: uint,      ;; timestamp of when added
        author: principal
    }
)

(define-public (add-record-note (record-id uint) (note (string-utf8 500)))
    (ok (map-set record-notes
        { patient: tx-sender, record-id: record-id }
        {
            note: note,
            date: stacks-block-height,
            author: tx-sender
        }
    ))
)

;;    New map to store an emergency contact along with relationship.
(define-map emergency-contact-details
    { patient: principal }
    {
        contact: principal,
        relationship: (string-utf8 100)
    }
)

(define-public (set-emergency-contact-details (contact principal) (relationship (string-utf8 100)))
    (ok (map-set emergency-contact-details
        { patient: tx-sender }
        {
            contact: contact,
            relationship: relationship
        }
    ))
)

;;    Allows patients to add feedback for a given prescription.
(define-map prescription-feedback
    { patient: principal, prescription-id: uint }
    {
        feedback: (string-utf8 500),
        date: uint
    }
)

(define-public (add-prescription-feedback (prescription-id uint) (feedback (string-utf8 500)))
    (ok (map-set prescription-feedback
        { patient: tx-sender, prescription-id: prescription-id }
        {
            feedback: feedback,
            date: stacks-block-height
        }
    ))
)

;;    Simple audit log to capture events.
(define-data-var audit-counter uint u0)

(define-map audit-log
    { log-id: uint }
    {
        event: (string-utf8 200),
        timestamp: uint,
        caller: principal
    }
)

;; Public function to log an event manually.
(define-public (record-audit-event (event (string-utf8 200)))
    (let
        ((new-log-id (+ (var-get audit-counter) u1)))
        (var-set audit-counter new-log-id)
        (ok (map-set audit-log
            { log-id: new-log-id }
            {
                event: event,
                timestamp: stacks-block-height,
                caller: tx-sender
            }
        ))
    )
)

;;    Read-only function that checks if the insurance for the calling patient
;;    will expire within the specified threshold (in blocks).
(define-read-only (get-insurance-renewal-status (threshold uint))
    (let
        ((insurance (map-get? insurance-info { patient: tx-sender })))
        (if (is-some insurance)
            (let (
                (valid-until (get valid-until (unwrap! insurance (err u404))))
            )
            (if (< (- valid-until stacks-block-height) threshold)
                (ok { status: "Renewal due", valid-until: valid-until })
                (ok { status: "Active", valid-until: valid-until })
            ))
            (err u404)
        )
    )
)

;;    Allow labs (the original test creator) to update a test result if needed.
(define-public (update-test-result (test-id uint) (test-name (string-utf8 100)) (result (string-utf8 500)) (lab (string-utf8 100)))
    (let
        (
            (existing (map-get? test-results { patient: tx-sender, test-id: test-id }))
        )
        (match existing
            old-test
                (if (is-eq (get lab old-test) lab)
                    (ok (map-set test-results
                        { patient: tx-sender, test-id: test-id }
                        {
                            test-name: test-name,
                            result: result,
                            date: stacks-block-height,
                            lab: lab
                        }
                    ))
                    (err u401)) ;; unauthorized
            (err u404) ;; not found
        )
    )
)



(define-map data-exports
    { patient: principal, export-id: uint }
    {
        data-hash: (buff 32),
        timestamp: uint,
        destination: (string-utf8 100),
        status: (string-utf8 20)
    }
)

(define-data-var export-counter uint u0)

(define-public (create-data-export (data-hash (buff 32)) (destination (string-utf8 100)))
    (let
        ((new-id (+ (var-get export-counter) u1)))
        (var-set export-counter new-id)
        (ok (map-set data-exports
            { patient: tx-sender, export-id: new-id }
            {
                data-hash: data-hash,
                timestamp: stacks-block-height,
                destination: destination,
                status: u"pending"
            }
        ))
    )
)

(define-public (confirm-data-export (export-id uint))
    (let
        ((export (unwrap! (map-get? data-exports { patient: tx-sender, export-id: export-id }) (err u404))))
        (ok (map-set data-exports
            { patient: tx-sender, export-id: export-id }
            (merge export { status: u"completed" })
        ))
    )
)


(define-map record-versions
    { patient: principal, record-id: uint, version: uint }
    {
        diagnosis: (string-utf8 500),
        date: uint,
        doctor: principal,
        hospital: (string-utf8 100),
        change-reason: (string-utf8 200)
    }
)

(define-map version-counters
    { record-id: uint }
    { current-version: uint }
)

(define-public (update-medical-record-with-version 
    (record-id uint)
    (diagnosis (string-utf8 500))
    (hospital (string-utf8 100))
    (change-reason (string-utf8 200)))
    (let
        ((current-version (default-to { current-version: u0 } 
            (map-get? version-counters { record-id: record-id })))
         (new-version (+ (get current-version current-version) u1)))
        (map-set version-counters
            { record-id: record-id }
            { current-version: new-version })
        (ok (map-set record-versions
            { patient: tx-sender, record-id: record-id, version: new-version }
            {
                diagnosis: diagnosis,
                date: stacks-block-height,
                doctor: tx-sender,
                hospital: hospital,
                change-reason: change-reason
            }
        ))
    )
)

(define-read-only (get-record-version (patient principal) (record-id uint) (version uint))
    (ok (map-get? record-versions { patient: patient, record-id: record-id, version: version }))
)


(define-map access-logs
    { patient: principal, log-id: uint }
    {
        accessor: principal,
        timestamp: uint,
        access-type: (string-utf8 20),
        data-type: (string-utf8 50)
    }
)

(define-data-var access-log-counter uint u0)

(define-public (log-data-access (patient principal) (access-type (string-utf8 20)) (data-type (string-utf8 50)))
    (let
        ((new-id (+ (var-get access-log-counter) u1)))
        (var-set access-log-counter new-id)
        (ok (map-set access-logs
            { patient: patient, log-id: new-id }
            {
                accessor: tx-sender,
                timestamp: stacks-block-height,
                access-type: access-type,
                data-type: data-type
            }
        ))
    )
)

(define-read-only (get-access-logs (patient principal) (log-id uint))
    (let
        ((is-authorized (or 
            (is-eq tx-sender patient)
            (get has-access (default-to { has-access: false }
                (map-get? access-permissions { patient: patient, provider: tx-sender })))
        )))
        (if is-authorized
            (ok (map-get? access-logs { patient: patient, log-id: log-id }))
            (err u403)
        )
    )
)


(define-map transfer-requests
    { patient: principal, request-id: uint }
    {
        from-provider: principal,
        to-provider: principal,
        status: (string-utf8 20),
        timestamp: uint,
        record-types: (list 10 (string-utf8 50))
    }
)

(define-data-var transfer-request-counter uint u0)

(define-public (request-record-transfer (patient principal) (to-provider principal) (record-types (list 10 (string-utf8 50))))
    (let
        ((new-id (+ (var-get transfer-request-counter) u1)))
        (var-set transfer-request-counter new-id)
        (ok (map-set transfer-requests
            { patient: patient, request-id: new-id }
            {
                from-provider: tx-sender,
                to-provider: to-provider,
                status: u"pending",
                timestamp: stacks-block-height,
                record-types: record-types
            }
        ))
    )
)

(define-public (approve-record-transfer (request-id uint))
    (let
        ((request (unwrap! (map-get? transfer-requests { patient: tx-sender, request-id: request-id }) (err u404))))
        (ok (map-set transfer-requests
            { patient: tx-sender, request-id: request-id }
            (merge request { status: u"approved" })
        ))
    )
)

(define-map consent-permissions
    { patient: principal, provider: principal, data-type: (string-utf8 50) }
    {
        granted: bool,
        granted-date: uint,
        expires-at: uint,
        access-level: (string-utf8 20)
    }
)

(define-map consent-history
    { patient: principal, consent-id: uint }
    {
        provider: principal,
        data-type: (string-utf8 50),
        action: (string-utf8 20),
        timestamp: uint,
        expires-at: uint
    }
)

(define-data-var consent-history-counter uint u0)

(define-public (grant-data-consent 
    (provider principal) 
    (data-type (string-utf8 50)) 
    (duration-blocks uint) 
    (access-level (string-utf8 20)))
    (let
        ((expires-at (+ stacks-block-height duration-blocks))
         (consent-id (+ (var-get consent-history-counter) u1)))
        (var-set consent-history-counter consent-id)
        (map-set consent-permissions
            { patient: tx-sender, provider: provider, data-type: data-type }
            {
                granted: true,
                granted-date: stacks-block-height,
                expires-at: expires-at,
                access-level: access-level
            })
        (map-set consent-history
            { patient: tx-sender, consent-id: consent-id }
            {
                provider: provider,
                data-type: data-type,
                action: u"granted",
                timestamp: stacks-block-height,
                expires-at: expires-at
            })
        (ok consent-id)
    )
)

(define-public (revoke-data-consent (provider principal) (data-type (string-utf8 50)))
    (let
        ((consent-id (+ (var-get consent-history-counter) u1)))
        (var-set consent-history-counter consent-id)
        (map-set consent-permissions
            { patient: tx-sender, provider: provider, data-type: data-type }
            {
                granted: false,
                granted-date: u0,
                expires-at: u0,
                access-level: u""
            })
        (map-set consent-history
            { patient: tx-sender, consent-id: consent-id }
            {
                provider: provider,
                data-type: data-type,
                action: u"revoked",
                timestamp: stacks-block-height,
                expires-at: u0
            })
        (ok consent-id)
    )
)

(define-public (extend-consent-duration 
    (provider principal) 
    (data-type (string-utf8 50)) 
    (additional-blocks uint))
    (let
        ((existing-consent (unwrap! (map-get? consent-permissions 
            { patient: tx-sender, provider: provider, data-type: data-type }) (err u404)))
         (new-expiry (+ (get expires-at existing-consent) additional-blocks))
         (consent-id (+ (var-get consent-history-counter) u1)))
        (asserts! (get granted existing-consent) (err u400))
        (var-set consent-history-counter consent-id)
        (map-set consent-permissions
            { patient: tx-sender, provider: provider, data-type: data-type }
            (merge existing-consent { expires-at: new-expiry }))
        (map-set consent-history
            { patient: tx-sender, consent-id: consent-id }
            {
                provider: provider,
                data-type: data-type,
                action: u"extended",
                timestamp: stacks-block-height,
                expires-at: new-expiry
            })
        (ok consent-id)
    )
)

(define-read-only (check-data-access-permission (patient principal) (data-type (string-utf8 50)))
    (let
        ((consent (map-get? consent-permissions 
            { patient: patient, provider: tx-sender, data-type: data-type })))
        (match consent
            permission
                (if (and 
                    (get granted permission)
                    (> (get expires-at permission) stacks-block-height))
                    (ok { 
                        has-access: true, 
                        access-level: (get access-level permission),
                        expires-at: (get expires-at permission)
                    })
                    (ok { 
                        has-access: false, 
                        access-level: u"",
                        expires-at: u0
                    }))
            (ok { 
                has-access: false, 
                access-level: u"",
                expires-at: u0
            })
        )
    )
)

(define-read-only (get-consent-history (patient principal) (consent-id uint))
    (if (is-eq tx-sender patient)
        (ok (map-get? consent-history { patient: patient, consent-id: consent-id }))
        (err u403)
    )
)

(define-read-only (get-active-consents (patient principal) (provider principal))
    (if (or (is-eq tx-sender patient) (is-eq tx-sender provider))
        (ok {
            prescriptions: (unwrap-panic (check-data-access-permission patient u"prescriptions")),
            test-results: (unwrap-panic (check-data-access-permission patient u"test-results")),
            medical-history: (unwrap-panic (check-data-access-permission patient u"medical-history")),
            appointments: (unwrap-panic (check-data-access-permission patient u"appointments"))
        })
        (err u403)
    )
)

(define-public (bulk-grant-consent 
    (provider principal) 
    (data-types (list 10 (string-utf8 50))) 
    (duration-blocks uint) 
    (access-level (string-utf8 20)))
    (let
        ((expires-at (+ stacks-block-height duration-blocks)))
        (ok (map grant-single-consent data-types))
    )
)

(define-private (grant-single-consent (data-type (string-utf8 50)))
    (map-set consent-permissions
        { patient: tx-sender, provider: contract-caller, data-type: data-type }
        {
            granted: true,
            granted-date: stacks-block-height,
            expires-at: (+ stacks-block-height u1000),
            access-level: u"read"
        })
)

(define-read-only (get-expiring-consents (patient principal) (blocks-threshold uint))
    (if (is-eq tx-sender patient)
        (ok {
            threshold: blocks-threshold,
            current-block: stacks-block-height,
            check-before-block: (+ stacks-block-height blocks-threshold)
        })
        (err u403)
    )
)