;; Inter-Hospital Medical Data Sharing Contract
;; Enables secure sharing of patient medical records between healthcare facilities

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-REQUEST (err u400))
(define-constant ERR-EXPIRED-REFERRAL (err u408))
(define-constant ERR-DUPLICATE-REQUEST (err u409))

;; Data variables
(define-data-var referral-counter uint u0)
(define-data-var sharing-request-counter uint u0)

;; Hospital registry - tracks registered healthcare facilities
(define-map hospital-registry
    { hospital-id: principal }
    {
        hospital-name: (string-utf8 100),
        certification-level: uint,
        is-active: bool,
        registration-date: uint,
        specialties: (list 10 (string-utf8 50))
    }
)

;; Patient referrals between hospitals
(define-map patient-referrals
    { patient: principal, referral-id: uint }
    {
        from-hospital: principal,
        to-hospital: principal,
        referring-doctor: principal,
        referral-reason: (string-utf8 200),
        referral-date: uint,
        expiry-date: uint,
        status: (string-utf8 20),
        urgency-level: uint,
        medical-specialty: (string-utf8 50)
    }
)

;; Data sharing requests between hospitals
(define-map sharing-requests
    { request-id: uint }
    {
        patient: principal,
        requesting-hospital: principal,
        source-hospital: principal,
        referral-id: uint,
        requested-data-types: (list 5 (string-utf8 50)),
        request-date: uint,
        approval-status: (string-utf8 20),
        access-duration-blocks: uint,
        requesting-doctor: principal
    }
)

;; Shared data access log
(define-map shared-data-access
    { patient: principal, access-id: uint }
    {
        accessing-hospital: principal,
        accessing-doctor: principal,
        data-types-accessed: (list 5 (string-utf8 50)),
        access-timestamp: uint,
        referral-id: uint,
        session-duration: uint
    }
)

(define-data-var access-counter uint u0)

;; Register a hospital in the network
(define-public (register-hospital 
    (hospital-name (string-utf8 100))
    (certification-level uint)
    (specialties (list 10 (string-utf8 50))))
    (begin
        (asserts! (>= certification-level u1) ERR-INVALID-REQUEST)
        (asserts! (<= certification-level u5) ERR-INVALID-REQUEST)
        (ok (map-set hospital-registry
            { hospital-id: tx-sender }
            {
                hospital-name: hospital-name,
                certification-level: certification-level,
                is-active: true,
                registration-date: stacks-block-height,
                specialties: specialties
            }
        ))
    )
)

;; Create a patient referral
(define-public (create-patient-referral
    (patient principal)
    (to-hospital principal) 
    (referral-reason (string-utf8 200))
    (expiry-days uint)
    (urgency-level uint)
    (medical-specialty (string-utf8 50)))
    (let
        ((referral-id (+ (var-get referral-counter) u1))
         (expiry-date (+ stacks-block-height (* expiry-days u144))))
        (asserts! (is-some (map-get? hospital-registry { hospital-id: tx-sender })) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? hospital-registry { hospital-id: to-hospital })) ERR-NOT-FOUND)
        (asserts! (and (>= urgency-level u1) (<= urgency-level u4)) ERR-INVALID-REQUEST)
        
        (var-set referral-counter referral-id)
        (ok (map-set patient-referrals
            { patient: patient, referral-id: referral-id }
            {
                from-hospital: tx-sender,
                to-hospital: to-hospital,
                referring-doctor: tx-sender,
                referral-reason: referral-reason,
                referral-date: stacks-block-height,
                expiry-date: expiry-date,
                status: u"active",
                urgency-level: urgency-level,
                medical-specialty: medical-specialty
            }
        ))
    )
)

;; Request medical data sharing for a referred patient
(define-public (request-medical-data-sharing
    (patient principal)
    (referral-id uint)
    (requested-data-types (list 5 (string-utf8 50)))
    (access-duration-blocks uint))
    (let
        ((request-id (+ (var-get sharing-request-counter) u1))
         (referral (unwrap! (map-get? patient-referrals { patient: patient, referral-id: referral-id }) ERR-NOT-FOUND)))
        
        ;; Verify the requesting hospital matches the referral destination
        (asserts! (is-eq tx-sender (get to-hospital referral)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status referral) u"active") ERR-EXPIRED-REFERRAL)
        (asserts! (> (get expiry-date referral) stacks-block-height) ERR-EXPIRED-REFERRAL)
        
        (var-set sharing-request-counter request-id)
        (ok (map-set sharing-requests
            { request-id: request-id }
            {
                patient: patient,
                requesting-hospital: tx-sender,
                source-hospital: (get from-hospital referral),
                referral-id: referral-id,
                requested-data-types: requested-data-types,
                request-date: stacks-block-height,
                approval-status: u"pending",
                access-duration-blocks: access-duration-blocks,
                requesting-doctor: tx-sender
            }
        ))
    )
)

;; Approve data sharing request (by source hospital or patient)
(define-public (approve-data-sharing (request-id uint))
    (let
        ((request (unwrap! (map-get? sharing-requests { request-id: request-id }) ERR-NOT-FOUND)))
        (asserts! (or 
            (is-eq tx-sender (get source-hospital request))
            (is-eq tx-sender (get patient request))) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get approval-status request) u"pending") ERR-INVALID-REQUEST)
        
        (ok (map-set sharing-requests
            { request-id: request-id }
            (merge request { approval-status: u"approved" })
        ))
    )
)

;; Log access to shared medical data
(define-public (log-shared-data-access
    (patient principal)
    (referral-id uint)
    (data-types-accessed (list 5 (string-utf8 50)))
    (session-duration uint))
    (let
        ((access-id (+ (var-get access-counter) u1))
         (referral (unwrap! (map-get? patient-referrals { patient: patient, referral-id: referral-id }) ERR-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get to-hospital referral)) ERR-UNAUTHORIZED)
        (asserts! (> (get expiry-date referral) stacks-block-height) ERR-EXPIRED-REFERRAL)
        
        (var-set access-counter access-id)
        (ok (map-set shared-data-access
            { patient: patient, access-id: access-id }
            {
                accessing-hospital: tx-sender,
                accessing-doctor: tx-sender,
                data-types-accessed: data-types-accessed,
                access-timestamp: stacks-block-height,
                referral-id: referral-id,
                session-duration: session-duration
            }
        ))
    )
)

;; Complete referral process
(define-public (complete-referral (patient principal) (referral-id uint) (outcome-notes (string-utf8 200)))
    (let
        ((referral (unwrap! (map-get? patient-referrals { patient: patient, referral-id: referral-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get to-hospital referral)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status referral) u"active") ERR-INVALID-REQUEST)
        
        (ok (map-set patient-referrals
            { patient: patient, referral-id: referral-id }
            (merge referral { status: u"completed" })
        ))
    )
)

;; Read-only functions

;; Get hospital information
(define-read-only (get-hospital-info (hospital-id principal))
    (map-get? hospital-registry { hospital-id: hospital-id })
)

;; Get patient referral details
(define-read-only (get-patient-referral (patient principal) (referral-id uint))
    (let
        ((referral (map-get? patient-referrals { patient: patient, referral-id: referral-id })))
        (if (or 
            (is-eq tx-sender patient)
            (match referral
                ref-data (or 
                    (is-eq tx-sender (get from-hospital ref-data))
                    (is-eq tx-sender (get to-hospital ref-data)))
                false))
            (ok referral)
            ERR-UNAUTHORIZED
        )
    )
)

;; Get sharing request status
(define-read-only (get-sharing-request (request-id uint))
    (let
        ((request (map-get? sharing-requests { request-id: request-id })))
        (match request
            req-data
                (if (or 
                    (is-eq tx-sender (get requesting-hospital req-data))
                    (is-eq tx-sender (get source-hospital req-data))
                    (is-eq tx-sender (get patient req-data)))
                    (ok request)
                    ERR-UNAUTHORIZED)
            (ok none)
        )
    )
)

;; Get patient's sharing activity log
(define-read-only (get-patient-sharing-log (patient principal))
    (if (is-eq tx-sender patient)
        (ok {
            total-referrals: (var-get referral-counter),
            total-access-logs: (var-get access-counter),
            current-block: stacks-block-height
        })
        ERR-UNAUTHORIZED
    )
)

;; Check if hospitals can share data based on referral
(define-read-only (can-hospitals-share-data (patient principal) (referral-id uint))
    (let
        ((referral (map-get? patient-referrals { patient: patient, referral-id: referral-id })))
        (match referral
            ref-data
                (ok {
                    can-share: (and 
                        (is-eq (get status ref-data) u"active")
                        (> (get expiry-date ref-data) stacks-block-height)),
                    referral-active: (is-eq (get status ref-data) u"active"),
                    expiry-date: (get expiry-date ref-data),
                    current-block: stacks-block-height
                })
            (ok {
                can-share: false,
                referral-active: false,
                expiry-date: u0,
                current-block: stacks-block-height
            })
        )
    )
)
