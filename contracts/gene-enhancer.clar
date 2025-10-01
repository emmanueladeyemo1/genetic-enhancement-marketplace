;; Gene Enhancer Smart Contract
;; Manages genetic enhancement treatments, patient consent, safety protocols, 
;; outcome tracking, regulatory compliance, and payment processing

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_TREATMENT_NOT_FOUND (err u101))
(define-constant ERR_PATIENT_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u103))
(define-constant ERR_CONSENT_NOT_PROVIDED (err u104))
(define-constant ERR_TREATMENT_NOT_APPROVED (err u105))
(define-constant ERR_PROVIDER_NOT_CERTIFIED (err u106))
(define-constant ERR_INVALID_OUTCOME_DATA (err u107))
(define-constant ERR_REGULATORY_VIOLATION (err u108))
(define-constant ERR_SAFETY_PROTOCOL_VIOLATION (err u109))

;; Data Variables
(define-data-var next-treatment-id uint u1)
(define-data-var next-patient-id uint u1)
(define-data-var next-consent-id uint u1)
(define-data-var next-outcome-id uint u1)
(define-data-var regulatory-authority principal CONTRACT_OWNER)
(define-data-var platform-fee-percentage uint u5) ;; 5% platform fee

;; Data Maps

;; Treatment Management
(define-map treatments
  { treatment-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    provider: principal,
    cost: uint,
    success-rate: uint, ;; percentage out of 100
    safety-score: uint, ;; score out of 100
    regulatory-status: (string-ascii 20), ;; "approved", "pending", "rejected"
    certification-level: uint, ;; 1-5 scale
    created-at: uint,
    is-active: bool
  }
)

;; Patient Management
(define-map patients
  { patient-id: uint }
  {
    address: principal,
    age: uint,
    medical-history-hash: (buff 32),
    consent-status: bool,
    treatments-received: (list 10 uint),
    registered-at: uint,
    is-active: bool
  }
)

;; Consent Management
(define-map consents
  { consent-id: uint }
  {
    patient-id: uint,
    treatment-id: uint,
    consent-hash: (buff 32),
    witness: principal,
    consent-date: uint,
    is-valid: bool,
    expiry-date: uint
  }
)

;; Treatment Outcomes
(define-map outcomes
  { outcome-id: uint }
  {
    patient-id: uint,
    treatment-id: uint,
    provider: principal,
    success: bool,
    side-effects: (string-ascii 200),
    effectiveness-score: uint, ;; 0-100
    safety-score: uint, ;; 0-100
    follow-up-required: bool,
    reported-at: uint,
    verified-by: principal
  }
)

;; Provider Certifications
(define-map providers
  { provider: principal }
  {
    certification-level: uint, ;; 1-5
    treatments-offered: (list 20 uint),
    success-rate: uint,
    safety-record: uint,
    regulatory-compliance: bool,
    certified-at: uint,
    is-active: bool
  }
)

;; Payment Records
(define-map payments
  { patient-id: uint, treatment-id: uint }
  {
    amount-paid: uint,
    platform-fee: uint,
    provider-payment: uint,
    payment-date: uint,
    payment-status: (string-ascii 20) ;; "completed", "pending", "refunded"
  }
)

;; Safety Monitoring
(define-map safety-alerts
  { treatment-id: uint }
  {
    alert-level: uint, ;; 1-5 (5 being most severe)
    description: (string-ascii 300),
    affected-patients: uint,
    reported-by: principal,
    status: (string-ascii 20), ;; "active", "resolved", "investigating"
    created-at: uint
  }
)

;; Regulatory Audits
(define-map regulatory-audits
  { audit-id: uint }
  {
    treatment-id: uint,
    auditor: principal,
    compliance-score: uint, ;; 0-100
    findings: (string-ascii 500),
    recommendations: (string-ascii 500),
    audit-date: uint,
    status: (string-ascii 20) ;; "passed", "failed", "conditional"
  }
)

;; Private Functions

(define-private (is-authorized (user principal))
  (or (is-eq user CONTRACT_OWNER)
      (is-eq user (var-get regulatory-authority))
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u100)
)

(define-private (is-provider-certified (provider principal))
  (match (map-get? providers { provider: provider })
    provider-data (and (>= (get certification-level provider-data) u3)
                       (get is-active provider-data)
                       (get regulatory-compliance provider-data))
    false
  )
)

(define-private (validate-treatment-eligibility (patient-id uint) (treatment-id uint))
  (match (map-get? patients { patient-id: patient-id })
    patient-data
    (match (map-get? treatments { treatment-id: treatment-id })
      treatment-data
      (and (get is-active patient-data)
           (get is-active treatment-data)
           (is-eq (get regulatory-status treatment-data) "approved")
           (is-provider-certified (get provider treatment-data))
      )
      false
    )
    false
  )
)

;; Public Functions

;; Treatment Management Functions

(define-public (register-treatment 
    (name (string-ascii 100))
    (description (string-ascii 500))
    (cost uint)
    (success-rate uint)
    (safety-score uint)
  )
  (let (
    (treatment-id (var-get next-treatment-id))
  )
    (asserts! (is-provider-certified tx-sender) ERR_PROVIDER_NOT_CERTIFIED)
    (asserts! (<= success-rate u100) (err u400))
    (asserts! (<= safety-score u100) (err u400))
    
    (map-set treatments
      { treatment-id: treatment-id }
      {
        name: name,
        description: description,
        provider: tx-sender,
        cost: cost,
        success-rate: success-rate,
        safety-score: safety-score,
        regulatory-status: "pending",
        certification-level: u1,
        created-at: block-height,
        is-active: true
      }
    )
    (var-set next-treatment-id (+ treatment-id u1))
    (ok treatment-id)
  )
)

(define-public (approve-treatment (treatment-id uint) (certification-level uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (<= certification-level u5) (err u400))
    
    (match (map-get? treatments { treatment-id: treatment-id })
      treatment-data
      (begin
        (map-set treatments
          { treatment-id: treatment-id }
          (merge treatment-data {
            regulatory-status: "approved",
            certification-level: certification-level
          })
        )
        (ok true)
      )
      ERR_TREATMENT_NOT_FOUND
    )
  )
)

;; Patient Management Functions

(define-public (register-patient (age uint) (medical-history-hash (buff 32)))
  (let (
    (patient-id (var-get next-patient-id))
  )
    (map-set patients
      { patient-id: patient-id }
      {
        address: tx-sender,
        age: age,
        medical-history-hash: medical-history-hash,
        consent-status: false,
        treatments-received: (list ),
        registered-at: block-height,
        is-active: true
      }
    )
    (var-set next-patient-id (+ patient-id u1))
    (ok patient-id)
  )
)

;; Consent Management Functions

(define-public (provide-consent 
    (patient-id uint)
    (treatment-id uint)
    (consent-hash (buff 32))
    (witness principal)
    (expiry-blocks uint)
  )
  (let (
    (consent-id (var-get next-consent-id))
    (expiry-date (+ block-height expiry-blocks))
  )
    (asserts! (is-eq tx-sender 
                    (get address (unwrap! (map-get? patients { patient-id: patient-id }) ERR_PATIENT_NOT_FOUND))
              ) ERR_NOT_AUTHORIZED)
    
    (map-set consents
      { consent-id: consent-id }
      {
        patient-id: patient-id,
        treatment-id: treatment-id,
        consent-hash: consent-hash,
        witness: witness,
        consent-date: block-height,
        is-valid: true,
        expiry-date: expiry-date
      }
    )
    (var-set next-consent-id (+ consent-id u1))
    (ok consent-id)
  )
)

;; Payment Processing Functions

(define-public (process-payment (patient-id uint) (treatment-id uint))
  (let (
    (treatment-data (unwrap! (map-get? treatments { treatment-id: treatment-id }) ERR_TREATMENT_NOT_FOUND))
    (treatment-cost (get cost treatment-data))
    (platform-fee (calculate-platform-fee treatment-cost))
    (provider-payment (- treatment-cost platform-fee))
  )
    (asserts! (validate-treatment-eligibility patient-id treatment-id) ERR_TREATMENT_NOT_APPROVED)
    (asserts! (>= (stx-get-balance tx-sender) treatment-cost) ERR_INSUFFICIENT_PAYMENT)
    
    ;; Transfer payment to provider
    (try! (stx-transfer? provider-payment tx-sender (get provider treatment-data)))
    
    ;; Transfer platform fee to contract owner
    (try! (stx-transfer? platform-fee tx-sender CONTRACT_OWNER))
    
    ;; Record payment
    (map-set payments
      { patient-id: patient-id, treatment-id: treatment-id }
      {
        amount-paid: treatment-cost,
        platform-fee: platform-fee,
        provider-payment: provider-payment,
        payment-date: block-height,
        payment-status: "completed"
      }
    )
    (ok true)
  )
)

;; Outcome Tracking Functions

(define-public (report-outcome
    (patient-id uint)
    (treatment-id uint)
    (success bool)
    (side-effects (string-ascii 200))
    (effectiveness-score uint)
    (safety-score uint)
    (follow-up-required bool)
  )
  (let (
    (outcome-id (var-get next-outcome-id))
    (treatment-data (unwrap! (map-get? treatments { treatment-id: treatment-id }) ERR_TREATMENT_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get provider treatment-data)) ERR_NOT_AUTHORIZED)
    (asserts! (<= effectiveness-score u100) ERR_INVALID_OUTCOME_DATA)
    (asserts! (<= safety-score u100) ERR_INVALID_OUTCOME_DATA)
    
    (map-set outcomes
      { outcome-id: outcome-id }
      {
        patient-id: patient-id,
        treatment-id: treatment-id,
        provider: tx-sender,
        success: success,
        side-effects: side-effects,
        effectiveness-score: effectiveness-score,
        safety-score: safety-score,
        follow-up-required: follow-up-required,
        reported-at: block-height,
        verified-by: tx-sender
      }
    )
    (var-set next-outcome-id (+ outcome-id u1))
    (ok outcome-id)
  )
)

;; Provider Certification Functions

(define-public (certify-provider
    (provider principal)
    (certification-level uint)
    (treatments-offered (list 20 uint))
  )
  (begin
    (asserts! (is-authorized tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (<= certification-level u5) (err u400))
    
    (map-set providers
      { provider: provider }
      {
        certification-level: certification-level,
        treatments-offered: treatments-offered,
        success-rate: u0,
        safety-record: u100,
        regulatory-compliance: true,
        certified-at: block-height,
        is-active: true
      }
    )
    (ok true)
  )
)

;; Safety Monitoring Functions

(define-public (create-safety-alert
    (treatment-id uint)
    (alert-level uint)
    (description (string-ascii 300))
    (affected-patients uint)
  )
  (begin
    (asserts! (is-authorized tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (<= alert-level u5) (err u400))
    
    (map-set safety-alerts
      { treatment-id: treatment-id }
      {
        alert-level: alert-level,
        description: description,
        affected-patients: affected-patients,
        reported-by: tx-sender,
        status: "active",
        created-at: block-height
      }
    )
    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-treatment (treatment-id uint))
  (map-get? treatments { treatment-id: treatment-id })
)

(define-read-only (get-patient (patient-id uint))
  (map-get? patients { patient-id: patient-id })
)

(define-read-only (get-consent (consent-id uint))
  (map-get? consents { consent-id: consent-id })
)

(define-read-only (get-outcome (outcome-id uint))
  (map-get? outcomes { outcome-id: outcome-id })
)

(define-read-only (get-provider (provider principal))
  (map-get? providers { provider: provider })
)

(define-read-only (get-payment (patient-id uint) (treatment-id uint))
  (map-get? payments { patient-id: patient-id, treatment-id: treatment-id })
)

(define-read-only (get-safety-alert (treatment-id uint))
  (map-get? safety-alerts { treatment-id: treatment-id })
)

(define-read-only (get-contract-info)
  {
    next-treatment-id: (var-get next-treatment-id),
    next-patient-id: (var-get next-patient-id),
    next-consent-id: (var-get next-consent-id),
    next-outcome-id: (var-get next-outcome-id),
    regulatory-authority: (var-get regulatory-authority),
    platform-fee-percentage: (var-get platform-fee-percentage)
  }
)
