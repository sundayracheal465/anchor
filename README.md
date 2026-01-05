# Supply Chain Tracking Smart Contract

A Clarity smart contract for tracking items through a supply chain with ownership management and event logging.

## Core Features

- Item management with ownership tracking
- Event history logging
- Access control system
- Status updates
- Ownership transfers

## Data Structure

### Maps
- `items`: Stores item details (owner, metadata, status)
- `events`: Chronicles item history
- `authorized-actors`: Manages access permissions
- `event-counts`: Tracks event counts per item

## Key Functions

### Management Functions
- `mint-item`: Creates new items
- `append-event`: Adds events to item history
- `transfer-ownership`: Changes item ownership
- `update-status`: Updates item status

### Access Control
- `authorize-actor`: Grants access permissions
- `revoke-actor`: Removes access permissions
- `is-authorized`: Validates actor permissions

### Query Functions
- `get-item`: Retrieves item information
- `get-event`: Gets specific event details
- `get-latest-event`: Retrieves most recent event
- `get-item-owner`: Returns current owner
- `is-actor-authorized`: Checks authorization status

## Error Handling

Built-in error codes:
- `ERR-NOT-FOUND (u1)`
- `ERR-NOT-AUTHORIZED (u2)`
- `ERR-NOT-OWNER (u3)`
- `ERR-ITEM-EXISTS (u4)`

## Data Constraints
- Metadata: Limited to 256 ASCII characters
- Status: Limited to 64 ASCII characters
- Event notes: Limited to 160 ASCII characters
