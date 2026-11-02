# Forum core live verification

Date: 2026-11-01

The repository-local federation and SMTP fixtures were executed by the test
suite. No pinned live ActivityPub peer or live SMTP recipient was available in
this environment, so none of the following was claimed as executed:

- live Group Follow/Accept/Reject/Undo interoperability with a pinned peer image
  or release digest
- live `Like`/`Dislike`/`Undo` delivery to a remote server
- delivery of an actual password-reset email through a real SMTP relay
- remote connector behavior across multiple independently operated instances

Fixture acceptance remains distinct from live interoperability evidence. Run
the same scenarios against named peer image/release digests and a controlled
SMTP sink before making a live-compatibility claim.
