;; Medical AI Integration Contract
;; Privacy-preserving AI-powered diagnostic assistance for healthcare providers

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u700))
(define-constant ERR-NOT-FOUND (err u701))
(define-constant ERR-INVALID-REQUEST (err u702))
(define-constant ERR-MODEL-NOT-CERTIFIED (err u703))
(define-constant ERR-INSUFFICIENT-CONSENT (err u704))
(define-constant ERR-AI-REQUEST-EXPIRED (err u705))
(define-constant ERR-BIAS-THRESHOLD-EXCEEDED (err u706))
(define-constant ERR-INVALID-PERFORMANCE-DATA (err u707))

;; Data variables
(define-data-var ai-model-counter uint u0)
(define-data-var ai-request-counter uint u0)
(define-data-var inference-counter uint u0)
(define-data-var bias-analysis-counter uint u0)

;; AI Model Registry - Tracks validated AI models for medical use
(define-map ai-model-registry
    uint ;; model-id
    {
        model-name: (string-utf8 100),
        developer: principal,
        medical-specialty: (string-utf8 50),
        certification-level: uint, ;; 1-5 (1=experimental, 5=clinical-grade)
        accuracy-rate: uint, ;; percentage (0-100)
        bias-score: uint, ;; 0-100 (lower is better)
        training-data-size: uint,
        validation-status: (string-utf8 20), ;; "pending", "approved", "rejected", "expired"
        certification-date: uint,
        expiry-date: uint,
        supported-conditions: (list 10 (string-utf8 50)),
        is-active: bool,
        total-inferences: uint,
        success-rate: uint
    }
)

;; AI Inference Requests - Secure diagnostic assistance requests
(define-map ai-inference-requests
    uint ;; request-id
    {
        patient: principal,
        requesting-provider: principal,
        model-id: uint,
        data-hash: (buff 32), ;; Hash of encrypted medical data
        consent-level: (string-utf8 20), ;; "basic", "research", "extended"
        request-timestamp: uint,
        urgency-level: uint, ;; 1-4 (1=routine, 4=emergency)
        expected-delivery: uint,
        request-status: (string-utf8 20), ;; "pending", "processing", "completed", "failed"
        data-types: (list 5 (string-utf8 50)), ;; Types of medical data included
        privacy-level: uint ;; 1-3 (1=anonymized, 2=pseudonymized, 3=identifiable)
    }
)

;; AI Inference Results - Secure storage of AI diagnostic results
(define-map ai-inference-results
    uint ;; result-id
    {
        request-id: uint,
        model-id: uint,
        result-hash: (buff 32), ;; Hash of encrypted AI results
        confidence-score: uint, ;; 0-100
        processing-time: uint,
        result-timestamp: uint,
        result-status: (string-utf8 20), ;; "preliminary", "validated", "reviewed"
        differential-diagnoses: (list 5 (string-utf8 100)),
        risk-indicators: (list 3 (string-utf8 50)),
        recommendations: (string-utf8 500),
        human-review-required: bool,
        bias-analysis-score: uint
    }
)

;; AI Model Performance Tracking - Continuous monitoring of model accuracy
(define-map ai-model-performance
    {model-id: uint, evaluation-period: uint}
    {
        total-predictions: uint,
        correct-predictions: uint,
        false-positives: uint,
        false-negatives: uint,
        demographic-fairness: (list 5 uint), ;; Fairness scores across demographics
        specialty-accuracy: uint,
        last-updated: uint,
        performance-trend: (string-utf8 20) ;; "improving", "stable", "declining"
    }
)

;; Patient AI Consent - Granular consent management for AI usage
(define-map patient-ai-consent
    {patient: principal, consent-type: (string-utf8 30)}
    {
        consent-granted: bool,
        consent-date: uint,
        expiry-date: uint,
        scope-limitations: (list 5 (string-utf8 50)),
        data-sharing-level: uint, ;; 1-3
        research-participation: bool,
        withdrawal-date: (optional uint)
    }
)

;; AI Audit Log - Comprehensive audit trail for AI usage
(define-map ai-audit-log
    uint ;; audit-id
    {
        event-type: (string-utf8 30), ;; "model-registration", "inference-request", "bias-detected"
        actor: principal,
        patient-affected: (optional principal),
        model-id: (optional uint),
        event-timestamp: uint,
        event-details: (string-utf8 300),
        risk-level: uint, ;; 1-5
        compliance-status: (string-utf8 20)
    }
)

;; AI Bias Detection - Monitoring for algorithmic bias and fairness
(define-map ai-bias-analysis
    uint ;; analysis-id
    {
        model-id: uint,
        analysis-period: uint,
        demographic-groups: (list 5 (string-utf8 30)),
        bias-metrics: (list 5 uint), ;; Bias scores for different groups
        statistical-parity: uint, ;; 0-100 (100 = perfect parity)
        equalized-odds: uint,
        disparate-impact-ratio: uint,
        analysis-date: uint,
        bias-alert-triggered: bool,
        mitigation-required: bool
    }
)

;; Provider AI Permissions - Control AI access for healthcare providers
(define-map provider-ai-permissions
    {provider: principal, model-id: uint}
    {
        access-level: uint, ;; 1-3 (1=view-only, 2=request, 3=admin)
        granted-by: principal,
        granted-date: uint,
        usage-quota: uint, ;; Daily inference limit
        current-usage: uint,
        last-reset: uint,
        specialization-match: bool
    }
)

;; AI Model Certification Authority
(define-data-var certification-authority principal tx-sender)

;; Register a new AI model for medical use
(define-public (register-ai-model 
    (model-name (string-utf8 100))
    (medical-specialty (string-utf8 50))
    (accuracy-rate uint)
    (training-data-size uint)
    (supported-conditions (list 10 (string-utf8 50))))
    (let (
        (model-id (+ (var-get ai-model-counter) u1))
        (current-block stacks-block-height)
        (expiry-date (+ current-block u52560)) ;; ~1 year validity
    )
        (asserts! (and (>= accuracy-rate u70) (<= accuracy-rate u100)) ERR-INVALID-PERFORMANCE-DATA)
        (asserts! (> training-data-size u1000) ERR-INVALID-PERFORMANCE-DATA)
        
        (var-set ai-model-counter model-id)
        (map-set ai-model-registry model-id
            {
                model-name: model-name,
                developer: tx-sender,
                medical-specialty: medical-specialty,
                certification-level: u1, ;; Start as experimental
                accuracy-rate: accuracy-rate,
                bias-score: u50, ;; Default neutral score
                training-data-size: training-data-size,
                validation-status: u"pending",
                certification-date: current-block,
                expiry-date: expiry-date,
                supported-conditions: supported-conditions,
                is-active: false, ;; Inactive until certified
                total-inferences: u0,
                success-rate: u0
            }
        )
        
        ;; Log registration event
        (unwrap-panic (log-ai-audit-event 
            u"model-registration" 
            none 
            (some model-id) 
            u"New AI model registered for certification" 
            u2))
        
        (ok model-id)
    )
)

;; Certify AI model for clinical use (certification authority only)
(define-public (certify-ai-model 
    (model-id uint) 
    (certification-level uint) 
    (bias-score uint))
    (let (
        (model-data (unwrap! (map-get? ai-model-registry model-id) ERR-NOT-FOUND))
        (current-block stacks-block-height)
    )
        (asserts! (is-eq tx-sender (var-get certification-authority)) ERR-UNAUTHORIZED)
        (asserts! (and (>= certification-level u1) (<= certification-level u5)) ERR-INVALID-REQUEST)
        (asserts! (<= bias-score u100) ERR-INVALID-REQUEST)
        (asserts! (< bias-score u30) ERR-BIAS-THRESHOLD-EXCEEDED) ;; Reject high-bias models
        
        (map-set ai-model-registry model-id
            (merge model-data {
                certification-level: certification-level,
                bias-score: bias-score,
                validation-status: u"approved",
                is-active: true,
                certification-date: current-block
            })
        )
        
        ;; Log certification event
        (unwrap-panic (log-ai-audit-event 
            u"model-certification" 
            none 
            (some model-id) 
            u"AI model certified for clinical use" 
            u3))
        
        (ok true)
    )
)

;; Grant AI model access to healthcare provider
(define-public (grant-provider-ai-access 
    (provider principal) 
    (model-id uint) 
    (access-level uint) 
    (daily-quota uint))
    (let (
        (model-data (unwrap! (map-get? ai-model-registry model-id) ERR-NOT-FOUND))
        (current-block stacks-block-height)
    )
        (asserts! (is-eq tx-sender (var-get certification-authority)) ERR-UNAUTHORIZED)
        (asserts! (get is-active model-data) ERR-MODEL-NOT-CERTIFIED)
        (asserts! (and (>= access-level u1) (<= access-level u3)) ERR-INVALID-REQUEST)
        
        (map-set provider-ai-permissions {provider: provider, model-id: model-id}
            {
                access-level: access-level,
                granted-by: tx-sender,
                granted-date: current-block,
                usage-quota: daily-quota,
                current-usage: u0,
                last-reset: current-block,
                specialization-match: true ;; Could be enhanced with specialty matching
            }
        )
        
        (ok true)
    )
)

;; Set patient AI consent preferences
(define-public (set-ai-consent 
    (consent-type (string-utf8 30)) 
    (consent-granted bool) 
    (data-sharing-level uint) 
    (research-participation bool) 
    (duration-days uint))
    (let (
        (current-block stacks-block-height)
        (expiry-date (+ current-block (* duration-days u144)))
    )
        (asserts! (and (>= data-sharing-level u1) (<= data-sharing-level u3)) ERR-INVALID-REQUEST)
        (asserts! (> duration-days u0) ERR-INVALID-REQUEST)
        
        (map-set patient-ai-consent {patient: tx-sender, consent-type: consent-type}
            {
                consent-granted: consent-granted,
                consent-date: current-block,
                expiry-date: expiry-date,
                scope-limitations: (list),
                data-sharing-level: data-sharing-level,
                research-participation: research-participation,
                withdrawal-date: none
            }
        )
        
        (ok true)
    )
)

;; Submit AI inference request
(define-public (submit-ai-inference-request 
    (patient principal) 
    (model-id uint) 
    (data-hash (buff 32)) 
    (consent-level (string-utf8 20)) 
    (urgency-level uint) 
    (data-types (list 5 (string-utf8 50))))
    (let (
        (request-id (+ (var-get ai-request-counter) u1))
        (model-data (unwrap! (map-get? ai-model-registry model-id) ERR-NOT-FOUND))
        (provider-access (unwrap! (map-get? provider-ai-permissions 
            {provider: tx-sender, model-id: model-id}) ERR-UNAUTHORIZED))
        (patient-consent (map-get? patient-ai-consent 
            {patient: patient, consent-type: u"diagnostic-ai"}))
        (current-block stacks-block-height)
        (expected-delivery (+ current-block u144)) ;; ~24 hours
    )
        ;; Validate model and permissions
        (asserts! (get is-active model-data) ERR-MODEL-NOT-CERTIFIED)
        (asserts! (>= (get access-level provider-access) u2) ERR-UNAUTHORIZED)
        (asserts! (and (>= urgency-level u1) (<= urgency-level u4)) ERR-INVALID-REQUEST)
        
        ;; Check patient consent
        (asserts! (match patient-consent
            consent-data (and 
                (get consent-granted consent-data)
                (> (get expiry-date consent-data) current-block))
            false) ERR-INSUFFICIENT-CONSENT)
        
        ;; Check usage quota
        (asserts! (< (get current-usage provider-access) (get usage-quota provider-access)) ERR-UNAUTHORIZED)
        
        (var-set ai-request-counter request-id)
        (map-set ai-inference-requests request-id
            {
                patient: patient,
                requesting-provider: tx-sender,
                model-id: model-id,
                data-hash: data-hash,
                consent-level: consent-level,
                request-timestamp: current-block,
                urgency-level: urgency-level,
                expected-delivery: expected-delivery,
                request-status: u"pending",
                data-types: data-types,
                privacy-level: u2 ;; Default to pseudonymized
            }
        )
        
        ;; Update provider usage
        (map-set provider-ai-permissions {provider: tx-sender, model-id: model-id}
            (merge provider-access {
                current-usage: (+ (get current-usage provider-access) u1)
            })
        )
        
        ;; Update model usage stats
        (map-set ai-model-registry model-id
            (merge model-data {
                total-inferences: (+ (get total-inferences model-data) u1)
            })
        )
        
        ;; Log inference request
        (unwrap-panic (log-ai-audit-event 
            u"inference-request" 
            (some patient) 
            (some model-id) 
            u"AI diagnostic assistance requested" 
            u2))
        
        (ok request-id)
    )
)

;; Store AI inference results (AI service only)
(define-public (store-ai-inference-result 
    (request-id uint) 
    (result-hash (buff 32)) 
    (confidence-score uint) 
    (differential-diagnoses (list 5 (string-utf8 100)))
    (recommendations (string-utf8 500))
    (processing-time uint))
    (let (
        (result-id (+ (var-get inference-counter) u1))
        (request-data (unwrap! (map-get? ai-inference-requests request-id) ERR-NOT-FOUND))
        (model-id (get model-id request-data))
        (current-block stacks-block-height)
        (bias-score u25) ;; Would be calculated by AI service
    )
        ;; Note: In production, this would be restricted to certified AI services
        (asserts! (<= confidence-score u100) ERR-INVALID-REQUEST)
        (asserts! (is-eq (get request-status request-data) u"pending") ERR-INVALID-REQUEST)
        
        (var-set inference-counter result-id)
        (map-set ai-inference-results result-id
            {
                request-id: request-id,
                model-id: model-id,
                result-hash: result-hash,
                confidence-score: confidence-score,
                processing-time: processing-time,
                result-timestamp: current-block,
                result-status: u"preliminary",
                differential-diagnoses: differential-diagnoses,
                risk-indicators: (list u"high" u"medium" u"low"),
                recommendations: recommendations,
                human-review-required: (< confidence-score u80),
                bias-analysis-score: bias-score
            }
        )
        
        ;; Update request status
        (map-set ai-inference-requests request-id
            (merge request-data {request-status: u"completed"})
        )
        
        ;; Log result storage
        (unwrap-panic (log-ai-audit-event 
            u"result-generated" 
            (some (get patient request-data)) 
            (some model-id) 
            u"AI inference result generated" 
            u2))
        
        (ok result-id)
    )
)

;; Perform bias analysis on AI model
(define-public (perform-bias-analysis 
    (model-id uint) 
    (demographic-groups (list 5 (string-utf8 30))) 
    (bias-metrics (list 5 uint)))
    (let (
        (analysis-id (+ (var-get bias-analysis-counter) u1))
        (model-data (unwrap! (map-get? ai-model-registry model-id) ERR-NOT-FOUND))
        (current-block stacks-block-height)
        (max-bias (fold uint-max bias-metrics u0))
        (min-bias (fold uint-min bias-metrics u100))
        (parity-score (- u100 (- max-bias min-bias)))
        (bias-alert (> max-bias u25)) ;; Alert if any group exceeds 25% bias
    )
        (asserts! (is-eq tx-sender (var-get certification-authority)) ERR-UNAUTHORIZED)
        (asserts! (get is-active model-data) ERR-MODEL-NOT-CERTIFIED)
        
        (var-set bias-analysis-counter analysis-id)
        (map-set ai-bias-analysis analysis-id
            {
                model-id: model-id,
                analysis-period: current-block,
                demographic-groups: demographic-groups,
                bias-metrics: bias-metrics,
                statistical-parity: parity-score,
                equalized-odds: (- u100 max-bias),
                disparate-impact-ratio: (if (> max-bias u0) (/ min-bias max-bias) u100),
                analysis-date: current-block,
                bias-alert-triggered: bias-alert,
                mitigation-required: (> max-bias u30)
            }
        )
        
        ;; If bias threshold exceeded, deactivate model
        (if (> max-bias u40)
            (map-set ai-model-registry model-id
                (merge model-data {is-active: false, validation-status: u"suspended"}))
            true
        )
        
        ;; Log bias analysis
        (unwrap-panic (log-ai-audit-event 
            (if bias-alert u"bias-detected" u"bias-analysis") 
            none 
            (some model-id) 
            u"AI model bias analysis completed" 
            (if bias-alert u4 u2)))
        
        (ok analysis-id)
    )
)

;; Helper function to find maximum value in list
(define-private (uint-max (a uint) (b uint))
    (if (> a b) a b)
)

;; Helper function to find minimum value in list
(define-private (uint-min (a uint) (b uint))
    (if (< a b) a b)
)

;; Private function to log audit events
(define-private (log-ai-audit-event 
    (event-type (string-utf8 30)) 
    (patient (optional principal)) 
    (model-id (optional uint)) 
    (details (string-utf8 300)) 
    (risk-level uint))
    (let (
        (audit-id (+ (var-get inference-counter) u1))
        (current-block stacks-block-height)
    )
        (map-set ai-audit-log audit-id
            {
                event-type: event-type,
                actor: tx-sender,
                patient-affected: patient,
                model-id: model-id,
                event-timestamp: current-block,
                event-details: details,
                risk-level: risk-level,
                compliance-status: u"compliant"
            }
        )
        (ok audit-id)
    )
)

;; Read-only functions

(define-read-only (get-ai-model-info (model-id uint))
    (map-get? ai-model-registry model-id)
)

(define-read-only (get-ai-inference-request (request-id uint))
    (let (
        (request-data (map-get? ai-inference-requests request-id))
    )
        (match request-data
            req-info
                (if (or 
                    (is-eq tx-sender (get patient req-info))
                    (is-eq tx-sender (get requesting-provider req-info)))
                    (ok request-data)
                    ERR-UNAUTHORIZED)
            (ok none)
        )
    )
)

(define-read-only (get-ai-inference-result (result-id uint))
    (let (
        (result-data (map-get? ai-inference-results result-id))
    )
        (match result-data
            res-info
                (let (
                    (request-data (unwrap! (map-get? ai-inference-requests (get request-id res-info)) ERR-NOT-FOUND))
                )
                    (if (or 
                        (is-eq tx-sender (get patient request-data))
                        (is-eq tx-sender (get requesting-provider request-data)))
                        (ok result-data)
                        ERR-UNAUTHORIZED))
            (ok none)
        )
    )
)

(define-read-only (get-patient-ai-consent (patient principal) (consent-type (string-utf8 30)))
    (if (or (is-eq tx-sender patient) (is-eq tx-sender (var-get certification-authority)))
        (ok (map-get? patient-ai-consent {patient: patient, consent-type: consent-type}))
        ERR-UNAUTHORIZED
    )
)

(define-read-only (get-ai-model-performance (model-id uint) (evaluation-period uint))
    (map-get? ai-model-performance {model-id: model-id, evaluation-period: evaluation-period})
)

(define-read-only (get-bias-analysis (analysis-id uint))
    (map-get? ai-bias-analysis analysis-id)
)

(define-read-only (get-provider-ai-permissions (provider principal) (model-id uint))
    (if (is-eq tx-sender provider)
        (ok (map-get? provider-ai-permissions {provider: provider, model-id: model-id}))
        ERR-UNAUTHORIZED
    )
)

(define-read-only (get-ai-audit-log (audit-id uint))
    (if (is-eq tx-sender (var-get certification-authority))
        (ok (map-get? ai-audit-log audit-id))
        ERR-UNAUTHORIZED
    )
)

(define-read-only (get-active-ai-models)
    (ok {
        total-models: (var-get ai-model-counter),
        total-inferences: (var-get ai-request-counter),
        total-results: (var-get inference-counter),
        bias-analyses: (var-get bias-analysis-counter)
    })
)

(define-read-only (is-model-bias-compliant (model-id uint))
    (let (
        (model-data (map-get? ai-model-registry model-id))
    )
        (match model-data
            model-info
                (and 
                    (get is-active model-info)
                    (< (get bias-score model-info) u30))
            false
        )
    )
)

;; Admin functions

(define-public (set-certification-authority (new-authority principal))
    (begin
        (asserts! (is-eq tx-sender (var-get certification-authority)) ERR-UNAUTHORIZED)
        (var-set certification-authority new-authority)
        (ok true)
    )
)

(define-public (emergency-suspend-model (model-id uint) (reason (string-utf8 200)))
    (let (
        (model-data (unwrap! (map-get? ai-model-registry model-id) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender (var-get certification-authority)) ERR-UNAUTHORIZED)
        
        (map-set ai-model-registry model-id
            (merge model-data {
                is-active: false, 
                validation-status: u"suspended"
            })
        )
        
        ;; Log emergency suspension
        (unwrap-panic (log-ai-audit-event 
            u"emergency-suspension" 
            none 
            (some model-id) 
            reason 
            u5))
        
        (ok true)
    )
)
