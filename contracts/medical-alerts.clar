;; Medical Alert System Contract
;; Provides comprehensive alert management for patients and healthcare providers

;; Alert severity levels (1=low, 2=medium, 3=high, 4=critical)
(define-constant ALERT-LOW u1)
(define-constant ALERT-MEDIUM u2)
(define-constant ALERT-HIGH u3)
(define-constant ALERT-CRITICAL u4)

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-ALERT (err u400))
(define-constant ERR-ALERT-EXPIRED (err u410))

;; Data Variables
(define-data-var alert-counter uint u0)
(define-data-var notification-counter uint u0)
(define-data-var medication-reminder-counter uint u0)

;; Medical Alerts Map
(define-map medical-alerts
    { patient: principal, alert-id: uint }
    {
        alert-type: (string-utf8 50),
        severity: uint,
        message: (string-utf8 300),
        created-date: uint,
        expiry-date: uint,
        is-active: bool,
        trigger-condition: (string-utf8 100),
        target-providers: (list 5 principal)
    }
)

;; Emergency Alert Configurations
(define-map emergency-alert-configs
    { patient: principal }
    {
        blood-pressure-threshold: uint,
        heart-rate-threshold: uint,
        temperature-threshold: uint,
        auto-notify-emergency-contact: bool,
        emergency-providers: (list 3 principal)
    }
)

;; Medication Reminders
(define-map medication-reminders
    { patient: principal, reminder-id: uint }
    {
        medication-name: (string-utf8 100),
        dosage-time: uint,
        frequency-hours: uint,
        start-date: uint,
        end-date: uint,
        is-active: bool,
        last-taken: uint,
        missed-doses: uint
    }
)

;; Alert Notifications (for providers)
(define-map alert-notifications
    { provider: principal, notification-id: uint }
    {
        patient: principal,
        alert-id: uint,
        notification-type: (string-utf8 30),
        timestamp: uint,
        is-read: bool,
        priority-score: uint
    }
)

;; Alert Response Log
(define-map alert-responses
    { alert-id: uint, responder: principal }
    {
        response-action: (string-utf8 100),
        response-notes: (string-utf8 200),
        response-timestamp: uint,
        follow-up-required: bool
    }
)

;; Alert Escalation Rules
(define-map escalation-rules
    { patient: principal, rule-id: uint }
    {
        trigger-condition: (string-utf8 100),
        escalation-delay-blocks: uint,
        escalation-targets: (list 3 principal),
        auto-escalate: bool,
        max-escalation-level: uint
    }
)

;; Create a new medical alert
(define-public (create-medical-alert 
    (alert-type (string-utf8 50))
    (severity uint) 
    (message (string-utf8 300))
    (expiry-blocks uint)
    (trigger-condition (string-utf8 100))
    (target-providers (list 5 principal)))
    (let
        ((new-alert-id (+ (var-get alert-counter) u1))
         (expiry-date (+ stacks-block-height expiry-blocks)))
        (asserts! (and (>= severity ALERT-LOW) (<= severity ALERT-CRITICAL)) ERR-INVALID-ALERT)
        (var-set alert-counter new-alert-id)
        (map-set medical-alerts
            { patient: tx-sender, alert-id: new-alert-id }
            {
                alert-type: alert-type,
                severity: severity,
                message: message,
                created-date: stacks-block-height,
                expiry-date: expiry-date,
                is-active: true,
                trigger-condition: trigger-condition,
                target-providers: target-providers
            })
        ;; Notify all target providers
        (map notify-provider target-providers)
        (ok new-alert-id)
    )
)

;; Configure emergency alert thresholds
(define-public (configure-emergency-alerts
    (blood-pressure-threshold uint)
    (heart-rate-threshold uint) 
    (temperature-threshold uint)
    (auto-notify-emergency-contact bool)
    (emergency-providers (list 3 principal)))
    (ok (map-set emergency-alert-configs
        { patient: tx-sender }
        {
            blood-pressure-threshold: blood-pressure-threshold,
            heart-rate-threshold: heart-rate-threshold,
            temperature-threshold: temperature-threshold,
            auto-notify-emergency-contact: auto-notify-emergency-contact,
            emergency-providers: emergency-providers
        }
    ))
)

;; Create medication reminder
(define-public (create-medication-reminder
    (medication-name (string-utf8 100))
    (dosage-time uint)
    (frequency-hours uint)
    (duration-days uint))
    (let
        ((new-reminder-id (+ (var-get medication-reminder-counter) u1))
         (end-date (+ stacks-block-height (* duration-days u144))))
        (var-set medication-reminder-counter new-reminder-id)
        (ok (map-set medication-reminders
            { patient: tx-sender, reminder-id: new-reminder-id }
            {
                medication-name: medication-name,
                dosage-time: dosage-time,
                frequency-hours: frequency-hours,
                start-date: stacks-block-height,
                end-date: end-date,
                is-active: true,
                last-taken: u0,
                missed-doses: u0
            }
        ))
    )
)

;; Mark medication as taken
(define-public (mark-medication-taken (reminder-id uint))
    (let
        ((reminder (unwrap! (map-get? medication-reminders { patient: tx-sender, reminder-id: reminder-id }) ERR-NOT-FOUND)))
        (asserts! (get is-active reminder) ERR-INVALID-ALERT)
        (ok (map-set medication-reminders
            { patient: tx-sender, reminder-id: reminder-id }
            (merge reminder { last-taken: stacks-block-height })
        ))
    )
)

;; Record missed medication dose
(define-public (record-missed-dose (reminder-id uint))
    (let
        ((reminder (unwrap! (map-get? medication-reminders { patient: tx-sender, reminder-id: reminder-id }) ERR-NOT-FOUND))
         (new-missed-count (+ (get missed-doses reminder) u1)))
        (map-set medication-reminders
            { patient: tx-sender, reminder-id: reminder-id }
            (merge reminder { missed-doses: new-missed-count }))
        ;; Auto-create alert if too many missed doses
        (if (>= new-missed-count u3)
            (begin
                (unwrap! (create-medical-alert 
                    u"medication-adherence"
                    ALERT-MEDIUM
                    u"Patient has missed 3+ medication doses"
                    u1000
                    u"missed-medication-threshold"
                    (get emergency-providers (default-to 
                        { blood-pressure-threshold: u0, heart-rate-threshold: u0, temperature-threshold: u0, 
                          auto-notify-emergency-contact: false, emergency-providers: (list) }
                        (map-get? emergency-alert-configs { patient: tx-sender })))) (err u500))
                u0)
            u0)
        (ok new-missed-count)
    )
)

;; Deactivate/resolve an alert
(define-public (resolve-alert (alert-id uint) (resolution-notes (string-utf8 200)))
    (let
        ((alert (unwrap! (map-get? medical-alerts { patient: tx-sender, alert-id: alert-id }) ERR-NOT-FOUND)))
        (map-set alert-responses
            { alert-id: alert-id, responder: tx-sender }
            {
                response-action: u"resolved",
                response-notes: resolution-notes,
                response-timestamp: stacks-block-height,
                follow-up-required: false
            })
        (ok (map-set medical-alerts
            { patient: tx-sender, alert-id: alert-id }
            (merge alert { is-active: false })
        ))
    )
)

;; Provider responds to an alert
(define-public (respond-to-alert 
    (patient principal)
    (alert-id uint) 
    (response-action (string-utf8 100))
    (response-notes (string-utf8 200))
    (follow-up-required bool))
    (let
        ((alert (unwrap! (map-get? medical-alerts { patient: patient, alert-id: alert-id }) ERR-NOT-FOUND)))
        (asserts! (is-some (index-of (get target-providers alert) tx-sender)) ERR-UNAUTHORIZED)
        (ok (map-set alert-responses
            { alert-id: alert-id, responder: tx-sender }
            {
                response-action: response-action,
                response-notes: response-notes,
                response-timestamp: stacks-block-height,
                follow-up-required: follow-up-required
            }
        ))
    )
)

;; Set up alert escalation rules
(define-public (create-escalation-rule
    (trigger-condition (string-utf8 100))
    (escalation-delay-blocks uint)
    (escalation-targets (list 3 principal))
    (auto-escalate bool)
    (max-escalation-level uint))
    (let
        ((rule-id (+ (var-get alert-counter) u1)))
        (ok (map-set escalation-rules
            { patient: tx-sender, rule-id: rule-id }
            {
                trigger-condition: trigger-condition,
                escalation-delay-blocks: escalation-delay-blocks,
                escalation-targets: escalation-targets,
                auto-escalate: auto-escalate,
                max-escalation-level: max-escalation-level
            }
        ))
    )
)

;; Helper function to notify providers
(define-private (notify-provider (provider principal))
    (let
        ((new-notification-id (+ (var-get notification-counter) u1)))
        (var-set notification-counter new-notification-id)
        (map-set alert-notifications
            { provider: provider, notification-id: new-notification-id }
            {
                patient: tx-sender,
                alert-id: (var-get alert-counter),
                notification-type: u"new-alert",
                timestamp: stacks-block-height,
                is-read: false,
                priority-score: u50
            })
    )
)

;; Mark notification as read
(define-public (mark-notification-read (notification-id uint))
    (let
        ((notification (unwrap! (map-get? alert-notifications { provider: tx-sender, notification-id: notification-id }) ERR-NOT-FOUND)))
        (ok (map-set alert-notifications
            { provider: tx-sender, notification-id: notification-id }
            (merge notification { is-read: true })
        ))
    )
)

;; Read-only functions

;; Get active alerts for a patient
(define-read-only (get-active-alerts (patient principal))
    (if (is-eq tx-sender patient)
        (ok { patient: patient, block-height: stacks-block-height })
        ERR-UNAUTHORIZED
    )
)

;; Get medication reminders for today
(define-read-only (get-todays-medication-reminders (patient principal))
    (if (is-eq tx-sender patient)
        (ok { 
            patient: patient, 
            current-block: stacks-block-height,
            reminder-count: (var-get medication-reminder-counter)
        })
        ERR-UNAUTHORIZED
    )
)

;; Get unread notifications for a provider
(define-read-only (get-unread-notifications (provider principal))
    (if (is-eq tx-sender provider)
        (ok { 
            provider: provider, 
            notification-count: (var-get notification-counter),
            current-block: stacks-block-height
        })
        ERR-UNAUTHORIZED
    )
)

;; Check if alert has expired
(define-read-only (is-alert-expired (patient principal) (alert-id uint))
    (let
        ((alert (map-get? medical-alerts { patient: patient, alert-id: alert-id })))
        (match alert
            alert-data
                (ok (> stacks-block-height (get expiry-date alert-data)))
            (ok false)
        )
    )
)

;; Get emergency configuration for patient
(define-read-only (get-emergency-config (patient principal))
    (if (is-eq tx-sender patient)
        (ok (map-get? emergency-alert-configs { patient: patient }))
        ERR-UNAUTHORIZED
    )
)

;; Get alert severity statistics
(define-read-only (get-alert-statistics (patient principal))
    (if (is-eq tx-sender patient)
        (ok {
            total-alerts-created: (var-get alert-counter),
            total-reminders: (var-get medication-reminder-counter),
            total-notifications: (var-get notification-counter),
            current-block: stacks-block-height
        })
        ERR-UNAUTHORIZED
    )
)

;; Check medication adherence rate
(define-read-only (calculate-adherence-rate (patient principal) (reminder-id uint))
    (let
        ((reminder (map-get? medication-reminders { patient: patient, reminder-id: reminder-id })))
        (if (is-eq tx-sender patient)
            (match reminder
                reminder-data
                    (let
                        ((days-active (/ (- stacks-block-height (get start-date reminder-data)) u144))
                         (expected-doses (/ (* days-active u24) (get frequency-hours reminder-data)))
                         (missed-count (get missed-doses reminder-data)))
                        (ok {
                            expected-doses: expected-doses,
                            missed-doses: missed-count,
                            adherence-percentage: (if (> expected-doses u0) 
                                (* (/ (- expected-doses missed-count) expected-doses) u100) 
                                u100)
                        })
                    )
                (ok { expected-doses: u0, missed-doses: u0, adherence-percentage: u0 })
            )
            ERR-UNAUTHORIZED
        )
    )
)


