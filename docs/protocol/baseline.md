# Protocol reference baseline

Retrieved 2026-10-12 from the Social Web Foundation GitHub mirror, using its
raw Markdown endpoints:

- FEP-1b12: <https://raw.githubusercontent.com/social-web-foundation/fep/main/fep/1b12/fep-1b12.md>
- FEP-7888: <https://raw.githubusercontent.com/social-web-foundation/fep/main/fep/7888/fep-7888.md>

The exact mirror texts are checked in under `snapshots/`, with SHA-256 digests
in `snapshots/SHA256SUMS`. Run `make verify-protocol` to validate the local
baseline without network access. Both texts carry CC0 public-domain dedications.
The mirror front matter labels 1b12 FINAL and 7888 DRAFT; those are snapshot
metadata, not claims about the present authoritative source status.

The canonical repository is <https://codeberg.org/fediverse/fep>. Direct
Codeberg retrieval was unavailable during this verification. These are
explicitly mirror snapshots: no canonical source commit, mirror commit, or
equivalence to the latest Codeberg revision has been verified. The local file
digests and retrieval date identify the implementation baseline. Updating it
requires a reviewed text diff and checklist review, rather than following a
mutable URL automatically.

## Requirement-to-test checklist

All protocol acceptance tests below are **pending implementation**. Stable
scenario identifiers describe required assertions and map to OpenSpec tasks;
the FFI tests do not satisfy these scenarios. Normative strength reflects the
pinned text. Recommendations are adopted unless a documented access rule
requires a narrower behavior.

| ID | Snapshot section / strength | Required test assertion | Tasks |
| --- | --- | --- | --- |
| G01 | Group actor | A community has Group identity and site-correct actor endpoints | 5.1, 6.1 |
| G02 | Following a Group / SHOULD | Valid public Follow receives Accept and adds a subscriber; authenticated Undo removes it | 6.1, 8.1 |
| G03 | Audience property / proposed convention | Topic, reply and submission reference the Group with audience independently of author and context | 4.2, 6.2 |
| G04 | Threads and comments / SHOULD | Topic name retains title | 4.2, 9.1 |
| G05 | Threads and comments / MUST | Reply inReplyTo preserves its direct thread or nested parent identity | 4.2, 8.1, 9.2 |
| G06 | Threads and comments / MAY, adopted | Group and topic reply collections traverse accepted topics and direct replies | 5.2, 7.1 |
| G07 | Announce / SHOULD | Blocked or policy-ineligible submission is not forwarded | 6.2, 6.7 |
| G08 | Announce / MAY, conditional | Reject is emitted only where supported and eligible; rejection remains observable locally | 4.6, 6.2 |
| G09 | Announce / MUST | Group wraps the original activity, not merely the post, and preserves all properties including unknown extensions and proofs | 6.2, 8.3 |
| G10 | Announce / SHOULD | Accepted announcement enters Group outbox and accepted collection; eligible followers receive it | 6.2, 6.3 |
| G11 | Announce approval semantics | Unrelated outer actor cannot approve another Group's submission; forged nested author mutation fails independently | 5.6, 6.3 |
| G12 | Activity type examples / supported profile | Create, Update, Delete, Like and Undo survive nested forwarding; private Follow is not indiscriminately forwarded | 6.2, 8.1 |
| G13 | Group moderation / optional section, adopted | Manager collection is advertised only where visibility allows; Add/Remove change current manager assignments | 6.1, 6.4, 6.6 |
| G14 | Group moderation / MUST when supported | Current authorized manager is required; follower additionally verifies Group announcement; unrelated signed moderation fails | 6.4, 6.5, 6.6 |
| G15 | Group moderation / SHOULD | Hosting-site administrator action requires an explicit local role and Group wrapping; same-origin actors without that role are rejected | 3.6, 6.4 |
| C01 | Purpose / SHOULD | Discussion context groups purposefully related objects, separately from audience and JSON-LD @context | 7.1, 7.2 |
| C02 | Purpose / MAY | Context removal invalidates inclusion without globally deleting unrelated shared objects | 7.3 |
| C03 | Dereferencing / SHOULD | Published federated context resolves with useful authority and audience metadata for eligible readers | 7.1, 7.7 |
| C04 | Dereferencing / SHOULD | Context exposes an associated canonical collection using the documented Commune direct-collection convention | 7.1, 7.6 |
| C05 | Group by context / SHOULD | Objects group by context id; missing, multiple, unresolved, Link and non-collection contexts do not become false membership | 7.2, 7.3 |
| C06 | Canonical collections / MAY | The application-specific collection relation is recognized without treating it as universally mandated by the FEP | 7.6 |
| C07 | Canonical collections / SHOULD NOT, SHOULD | Declared context alone does not establish acceptance; unverified inclusion is visibly labeled | 7.3 |
| C08 | Canonical collections / proof criteria out of scope | Commune evidence validates authoritative collection item or Add with no later Remove; forged/revoked evidence fails | 7.3, 7.5 |
| C09 | Choosing participation / MAY | Reply can copy, replace or omit context independently of inReplyTo; object and activity contexts stay distinguishable | 7.2, 7.4 |
| C10 | Keeping entities in loop / SHOULD, MAY | Copied remote context notifies its resolvable authority; optional audience/followers addressing is bounded and deduplicated | 7.4 |

The 7888 overview and appendices are non-normative examples, not additional
mandatory wire formats. Its collection discovery relation and proof criteria
are explicitly outside the FEP's scope. The Appendix C C2S algorithm is not a
requirement to emulate another application's client API.

## Commune access and authority additions

These are application requirements, not claims made by either FEP:

- LocalOnly has no ActivityPub discovery, representation, forwarding or backfill,
  including when local read policy permits all owning-site users.
- Member-readable federation authorizes current members or managers, omits
  Public addressing and refuses delivery to unverified protected peer profiles.
- Approved membership, following and management assignments remain separate.
- Hosting-site moderation uses an explicit role; the FEP's recommendation to
  trust hosting-server administration does not grant rights to arbitrary actors
  on that server. Remote managers need a current community assignment.
- Original activity bytes are retained separately from display content and
  parsed JSON. Duplicate object keys are rejected before intact forwarding.
- Group approval never substitutes for proof of the inner author's authority.
- Topic Page/reply Note and direct OrderedCollection contexts are Commune
  choices. Cross-peer compatibility must be demonstrated, not inferred.

Coverage remains the full change's responsibility; completing this baseline
does not establish FEP conformance or live peer interoperability.
