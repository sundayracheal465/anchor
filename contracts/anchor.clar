;; Enhanced supply chain tracking contract with access control and proper event management

;; Data maps
(define-map items uint { owner: principal, metadata: (string-ascii 256), status: (string-ascii 64) })
(define-map events
  (tuple (item-id uint) (index uint))
  {
    actor: principal,
    kind: (string-ascii 32),
    note: (optional (string-ascii 160)),
    status: (optional (string-ascii 64)),
    metadata: (optional (string-ascii 256)),
    new-owner: (optional principal),
    timestamp: uint
  })
(define-map authorized-actors (tuple (item-id uint) (actor principal)) { version: uint })
(define-map event-counts uint uint)
(define-map item-versions uint uint)

;; Error constants
(define-constant ERR-NOT-FOUND u1)
(define-constant ERR-NOT-AUTHORIZED u2)
(define-constant ERR-NOT-OWNER u3)
(define-constant ERR-ITEM-EXISTS u4)
(define-constant ERR-INVALID-INPUT u5)

;; Helper function to check if actor is authorized for an item
(define-private (is-authorized (item-id uint) (actor principal))
  (match (map-get? items item-id)
    item-data
      (let ((current-version (get-item-version item-id)))
        (or
          (is-eq actor (get owner item-data))
          (match (map-get? authorized-actors { item-id: item-id, actor: actor })
            auth-data (is-eq (get version auth-data) current-version)
            false)))
    false))

;; Get the current count of events for an item
(define-read-only (count-events-for (item-id uint))
  (default-to u0 (map-get? event-counts item-id)))

;; Track the current authorization/version epoch for an item
(define-private (get-item-version (item-id uint))
  (default-to u0 (map-get? item-versions item-id)))

;; FIXED: Helper function to get next event index and increment count
(define-private (get-next-event-index (item-id uint))
  (let ((current-count (count-events-for item-id)))
    (map-set event-counts item-id (+ current-count u1))
    current-count))


;; FIXED: Enhanced mint function with proper event indexing and input validation
(define-public (mint-item (id uint) (meta (string-ascii 256)))
  (if (> (len meta) u0)  ;; Input validation
    (let ((existing-item (map-get? items id)))
      (match existing-item
        val (err ERR-ITEM-EXISTS)
        (begin
          (map-set items id { owner: tx-sender, metadata: meta, status: "manufactured" })
          (map-set item-versions id u0)
          ;; FIXED: Use consistent indexing - first event gets index 0
          (let ((event-index (get-next-event-index id)))
            (map-set events { item-id: id, index: event-index } 
              {
                actor: tx-sender,
                kind: "mint",
                note: (some "minted"),
                status: (some "manufactured"),
                metadata: (some meta),
                new-owner: none,
                timestamp: stacks-block-height
              })
            (ok true)))))
    (err ERR-INVALID-INPUT)))

;; Enhanced append-event with access control and proper indexing
(define-public (append-event (id uint) (note (string-ascii 160)))
  (if (> (len note) u0)  ;; Input validation
    (let ((item-data (map-get? items id)))
      (match item-data
        val
          (if (is-authorized id tx-sender)
            (let ((event-index (get-next-event-index id)))
              (map-set events { item-id: id, index: event-index } 
                {
                  actor: tx-sender,
                  kind: "custom",
                  note: (some note),
                  status: none,
                  metadata: none,
                  new-owner: none,
                  timestamp: stacks-block-height
                })
              (ok true))
            (err ERR-NOT-AUTHORIZED))
        (err ERR-NOT-FOUND)))
    (err ERR-INVALID-INPUT)))

;; Transfer ownership of an item
(define-public (transfer-ownership (id uint) (new-owner principal))
  (let ((item-data (map-get? items id)))
    (match item-data
      val
        (if (is-eq tx-sender (get owner val))
          (begin
            (map-set items id (merge val { owner: new-owner }))
            (let ((current-version (get-item-version id)))
              (map-set item-versions id (+ current-version u1))
              (let ((event-index (get-next-event-index id)))
                (map-set events { item-id: id, index: event-index } 
                  {
                    actor: tx-sender,
                    kind: "ownership-transfer",
                    note: none,
                    status: none,
                    metadata: none,
                    new-owner: (some new-owner),
                    timestamp: stacks-block-height
                  })))
            (ok true))
          (err ERR-NOT-OWNER))
      (err ERR-NOT-FOUND))))

;; Authorize an actor to interact with an item
(define-public (authorize-actor (id uint) (actor principal))
  (let ((item-data (map-get? items id)))
    (match item-data
      val
        (if (is-eq tx-sender (get owner val))
          (begin
            (map-set authorized-actors { item-id: id, actor: actor } { version: (get-item-version id) })
            (ok true))
          (err ERR-NOT-OWNER))
      (err ERR-NOT-FOUND))))

;; Revoke actor authorization
(define-public (revoke-actor (id uint) (actor principal))
  (let ((item-data (map-get? items id)))
    (match item-data
      val
        (if (is-eq tx-sender (get owner val))
          (begin
            (map-delete authorized-actors { item-id: id, actor: actor })
            (ok true))
          (err ERR-NOT-OWNER))
      (err ERR-NOT-FOUND))))

;; Update item status (only owner or authorized actors)
(define-public (update-status (id uint) (new-status (string-ascii 64)))
  (if (> (len new-status) u0)  ;; Input validation
    (let ((item-data (map-get? items id)))
      (match item-data
        val
          (if (is-authorized id tx-sender)
            (begin
              (map-set items id (merge val { status: new-status }))
              (let ((event-index (get-next-event-index id)))
                (map-set events { item-id: id, index: event-index } 
                  {
                    actor: tx-sender,
                    kind: "status-update",
                    note: none,
                    status: (some new-status),
                    metadata: none,
                    new-owner: none,
                    timestamp: stacks-block-height
                  }))
              (ok true))
            (err ERR-NOT-AUTHORIZED))
        (err ERR-NOT-FOUND)))
    (err ERR-INVALID-INPUT)))

;; Read-only functions for querying data

;; Get the status change that sits `offset` steps behind the latest event (offset 0 = latest)
(define-read-only (get-status-history (item-id uint) (offset uint))
  (let ((event-count (count-events-for item-id)))
    (if (or (is-eq event-count u0) (<= event-count offset))
      none
      (let ((target-index (- (- event-count u1) offset)))
        (match (map-get? events { item-id: item-id, index: target-index })
          event-data
            (match (get status event-data)
              status-value
                (some
                  (tuple
                    (status status-value)
                    (timestamp (get timestamp event-data))
                    (event-index target-index)
                    (actor (get actor event-data))))
              none)
          none)))))

;; Get item information
(define-read-only (get-item (id uint))
  (map-get? items id))

;; Get a specific event
(define-read-only (get-event (item-id uint) (index uint))
  (map-get? events { item-id: item-id, index: index }))

;; Get the latest event for an item
(define-read-only (get-latest-event (item-id uint))
  (let ((count (count-events-for item-id)))
    (if (> count u0)
      (map-get? events { item-id: item-id, index: (- count u1) })
      none)))

;; Check if an actor is authorized for an item
(define-read-only (is-actor-authorized (item-id uint) (actor principal))
  (is-authorized item-id actor))

;; Get item owner
(define-read-only (get-item-owner (id uint))
  (match (map-get? items id)
    item-data (some (get owner item-data))
    none))
