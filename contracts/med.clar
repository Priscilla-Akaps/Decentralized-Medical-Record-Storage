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