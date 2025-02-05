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
