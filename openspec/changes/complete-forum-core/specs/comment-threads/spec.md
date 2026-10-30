## Purpose

Expose one threaded reply model for both shallow and deep discussions, so there is no separate flat-query implementation and existing clients can keep reading the root items.

## ADDED Requirements

### Requirement: One threaded reply read model
`GET /api/v1/posts/{id}/replies` SHALL use one threaded query and one response model. The response SHALL contain direct replies to the addressed post in `items`, and every item SHALL expose a recursive `children` array, integer `depth` starting at `1`, and integer `child_count` counting visible direct children. The response SHALL retain `limit`, `offset`, and the existing post fields. `limit` and `offset` SHALL paginate root items only; descendants SHALL be included only up to `max_depth`. `max_depth` SHALL be an integer from `1` through `8`, defaulting to `6`; an invalid value SHALL return `400`. The endpoint SHALL NOT promise a total count.

#### Scenario: Three-level discussion
- **WHEN** a readable topic has a reply, a reply to that reply, and a reply to the second reply
- **THEN** one root item contains both descendants in nested `children` with increasing `depth` and correct visible `child_count`

#### Scenario: Shallow page
- **WHEN** a client requests `max_depth=1`
- **THEN** the response contains root replies with empty `children` arrays, using the same response model and query

#### Scenario: Invalid depth
- **WHEN** a client requests `max_depth=0`, `max_depth=9`, or a non-integer value
- **THEN** the server returns `400` without returning a page

### Requirement: Legacy flat parameter compatibility
`view` SHALL be optional. Absent, `view=tree`, and `view=flat` SHALL all use the same threaded query and the same response model. `view=flat` SHALL be a deprecated compatibility alias that sets `max_depth=1`; it SHALL NOT select a separate flat query or a separate flat response shape. An unsupported `view` value SHALL return `400`. Existing clients that read only the root `items` SHALL continue to receive the same direct-reply identities and ordering, with `children`, `depth`, and `child_count` as additive fields.

#### Scenario: Legacy client keeps root replies
- **WHEN** an existing client requests the reply path without `view` or with `view=flat`
- **THEN** the root items are the direct replies it already expects, and the added thread fields do not require a second endpoint

#### Scenario: Deprecated alias is equivalent
- **WHEN** a client compares `view=flat` with `max_depth=1`
- **THEN** both return the same threaded page with empty `children` arrays

### Requirement: Thread ordering
Thread reads SHALL accept `sort` values `new`, `old`, `top`, and `controversial`. `old` SHALL be the default and SHALL preserve the existing direct-reply order by authored time ascending then ID. `new` SHALL order by authored time descending, `top` by aggregate score, and `controversial` by opposing vote balance. The same ordering SHALL apply independently to each sibling group. Authored time and ID SHALL break ties deterministically. An unsupported sort value SHALL return `400`.

#### Scenario: Default ordering is unchanged
- **WHEN** a legacy client omits `sort`
- **THEN** root replies remain ordered by authored time ascending then ID

#### Scenario: Sibling ordering
- **WHEN** two replies share a parent and the first has a higher score
- **THEN** `sort=top` places the higher-scored sibling first without reordering unrelated roots

#### Scenario: Stable tie
- **WHEN** siblings have equal scores and authored times
- **THEN** their order is stable by ID across repeated requests

### Requirement: Visibility and block inheritance
Thread reads SHALL apply the same current-site reception, read permission, deletion, hiding, and community inclusion rules to every level. A reply excluded by those rules SHALL NOT appear, and its descendants SHALL NOT be promoted to a surviving parent. Personal blocks of the author, community, or author's instance SHALL exclude the reply and its descendants. A direct request for an excluded reply SHALL return `404` without disclosing its body or parent chain.

#### Scenario: Hidden parent
- **WHEN** a parent reply is hidden but a child would otherwise be readable
- **THEN** the response omits both the parent and the child

#### Scenario: Blocked author subtree
- **WHEN** the viewer blocks a reply author
- **THEN** that reply and its descendants are absent and do not contribute to visible child counts

#### Scenario: Direct excluded reply
- **WHEN** a viewer requests an excluded reply by ID
- **THEN** the server returns `404` rather than a partial thread
