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
