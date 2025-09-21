;; Enhanced supply chain tracking contract with access control and proper event management

;; Data maps
(define-map items uint { owner: principal, metadata: (string-ascii 256), status: (string-ascii 64) })
(define-map events (tuple (item-id uint) (index uint)) { actor: principal, note: (string-ascii 160), timestamp: uint })
(define-map authorized-actors (tuple (item-id uint) (actor principal)) bool)
(define-map event-counts uint uint)

;; Error constants
(define-constant ERR-NOT-FOUND u1)
(define-constant ERR-NOT-AUTHORIZED u2)
(define-constant ERR-NOT-OWNER u3)
(define-constant ERR-ITEM-EXISTS u4)

;; Helper function to check if actor is authorized for an item
(define-private (is-authorized (item-id uint) (actor principal))
  (match (map-get? items item-id)
    item-data
      (or 
        (is-eq actor (get owner item-data))
        (default-to false (map-get? authorized-actors { item-id: item-id, actor: actor })))
    false))

;; Get the current count of events for an item
(define-read-only (count-events-for (item-id uint))
  (default-to u0 (map-get? event-counts item-id)))

;; Helper function to increment event count
(define-private (increment-event-count (item-id uint))
  (let ((current-count (count-events-for item-id)))
    (map-set event-counts item-id (+ current-count u1))
    current-count))

;; Enhanced mint function with proper event counting
(define-public (mint-item (id uint) (meta (string-ascii 256)))
  (let ((existing-item (map-get? items id)))
    (match existing-item
      val (err ERR-ITEM-EXISTS)
      (begin
        (map-set items id { owner: tx-sender, metadata: meta, status: "manufactured" })
        (map-set events { item-id: id, index: u0 } { actor: tx-sender, note: "mint", timestamp: stacks-block-height })
        (map-set event-counts id u1)
        (ok true)))))

;; Enhanced append-event with access control and proper indexing
(define-public (append-event (id uint) (note (string-ascii 160)))
  (let ((item-data (map-get? items id)))
    (match item-data
      val
        (if (is-authorized id tx-sender)
          (let ((idx (increment-event-count id)))
            (map-set events { item-id: id, index: idx } { actor: tx-sender, note: note, timestamp: stacks-block-height })
            (ok true))
          (err ERR-NOT-AUTHORIZED))
      (err ERR-NOT-FOUND))))

;; Transfer ownership of an item
(define-public (transfer-ownership (id uint) (new-owner principal))
  (let ((item-data (map-get? items id)))
    (match item-data
      val
        (if (is-eq tx-sender (get owner val))
          (begin
            (map-set items id (merge val { owner: new-owner }))
            (let ((idx (increment-event-count id)))
              (map-set events { item-id: id, index: idx } 
                { actor: tx-sender, note: "ownership-transfer", timestamp: stacks-block-height }))
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
            (map-set authorized-actors { item-id: id, actor: actor } true)
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
  (let ((item-data (map-get? items id)))
    (match item-data
      val
        (if (is-authorized id tx-sender)
          (begin
            (map-set items id (merge val { status: new-status }))
            (let ((idx (increment-event-count id)))
              (map-set events { item-id: id, index: idx } 
                { actor: tx-sender, note: "status-update", timestamp: stacks-block-height }))
            (ok true))
          (err ERR-NOT-AUTHORIZED))
      (err ERR-NOT-FOUND))))

;; Read-only functions for querying data

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