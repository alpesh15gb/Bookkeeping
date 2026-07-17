# CCR-001: Product metadata in master-data synchronization

- Contract: ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)
- Status: Proposed for a future contract version
- Discovered during: Phase 2 master-data synchronization

## Issue

Phase 2 requires ApexBooks product metadata to be synchronized. Contract v1's
`Product` schema has no `metadata` property and sets `additionalProperties: false`.
`ProductChangedRequest` also sets `unevaluatedProperties: false`. A conforming v1
producer therefore cannot send product metadata, and a conforming receiver must
reject a payload that attempts to include it.

## Requested change

In a future, non-v1 contract version, add an optional bounded `metadata` object to
the `Product` schema, including explicit limits for key count, key length, value
types, and serialized size.

## Phase 2 disposition

Contract v1 remains unchanged. The receiver strictly validates v1 and synchronizes
all product fields that v1 can express. Product metadata is not accepted or
persisted until an approved contract version defines it.
