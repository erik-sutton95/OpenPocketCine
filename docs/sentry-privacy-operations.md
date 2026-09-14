# Reliability reporting privacy operations

Owner: **OpenCapture**, privacy contact [support@openpocketcine.app](mailto:support@openpocketcine.app).
Updated September 14, 2026. This is the implementation and operating record;
it is not a certification that every GDPR obligation has been completed.

## Processing record

| Item | Implementation / purpose |
| --- | --- |
| Purpose | Diagnose app crashes, hangs and feed interruptions; measure recovery and session health |
| Legal basis | Optional consent; off by default; camera features remain available without consent |
| Subjects | Operators who enable reporting in a configured build |
| Data | App/build/OS, hardware and camera class, timing and recovery measurements, native stack traces, random incident/session identifiers |
| Excluded | Footage, screenshots, raw packets, passwords, personal device names, GPS, advertising identifiers |
| Recipient | Functional Software, Inc. doing business as Sentry, acting as processor |
| Storage | Organization API region URL and both project ingestion hosts verified as Germany on September 14 |
| Transfer | EU event storage does not establish that all provider processing is EU-only; review DPA transfer safeguards and subprocessors |
| Withdrawal | Operator Setup toggle stops capture/upload and clears SDK cache; separate local incident spool remains |
| Rights contact | Private email; never ask someone to publish their email or diagnostic report on GitHub |

Technical identifiers and connection IP addresses can still be personal data.
Do not describe reports as anonymous. The ingest connection necessarily exposes
an IP address to the service; client identity removal and verified recursive
server scrubbing remove stored event IP/geography, not the network connection.
JSON attachments must be redacted before upload: do not rely on event scrubbing
being applied to arbitrary attachment bytes.

## Before production enablement

- Confirm OpenCapture's full legal identity and controller contact details are
  sufficient for the published notice. The name and email were supplied by the owner.
- Account owner must confirm/accept Sentry's DPA in Legal & Compliance and retain
  evidence. Reading the public DPA or choosing Germany does not execute it.
  No DPA was signed by the implementation agent.
- Verify account access: least-privilege project membership, MFA, restricted
  attachments/debug files and public issue sharing disabled. Read-only inspection
  found `require2FA=false` and `allowSharedIssues=true`; these are open actions,
  not controls already in place. Disabling public issue sharing through the current
  credential also returned HTTP 403; an authorized owner must change it.
  AI/aggregated-data consent flags were false.
- Confirm the actual plan's event/attachment retention, issue-summary retention,
  exported support-copy deletion and provider backup handling. Current standard
  documented retention is 30 days (Developer) or 90 days (Team/Business), fixed
  at ingestion. Do not claim a custom 30-day policy unless it is enforced.
- Update App Store privacy answers, privacy manifests where applicable, and Play
  Data Safety answers for configured releases. SDK opt-in does not replace those
  disclosures. No store disclosures were submitted in this task.
- Verify consent withdrawal and cached native/incident delivery on each platform.
  Android still requires physical verification before rollout qualification.

## Access and deletion requests

1. Receive the request at the private support address and record its date.
2. Locate relevant reports using an incident ID, approximate time and build when
   available. Do not collect a new persistent tracking ID just for requests.
3. Verify identity proportionately. If a report cannot be identified, explain the
   limitation and ask only for information necessary to locate it.
4. Export or delete the relevant events/attachments and any identifiable support
   copies as appropriate. Deleting a whole issue can affect other users: inspect
   scope before deleting. Do not claim that disabling the toggle deletes server data.
5. Record completion and respond within one month, or explain any permitted
   extension and reason within that initial period.

A development cleanup attempt for an early synthetic issue returned HTTP 403.
The current agent credential therefore cannot demonstrate server-side deletion.
An authorized owner must complete and verify that test before claiming the
request procedure is operational. Early test events retained inferred geography;
the subsequent recursive rule is not retroactive. No production user was involved.

## Incident response

Restrict access and stop affected collection if a privacy leak is found, preserve
minimal evidence, determine affected data/people, and have the controller assess
notification obligations promptly. GDPR Article 33 can require supervisory
notification within 72 hours of awareness; Article 34 can require notification
to affected individuals where the risk is high. Document the assessment even
when notification is not required. Do not confuse an app feed incident with a
personal-data breach.

## Primary references

- [EDPB: lawful processing and consent](https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en)
- [Sentry DPA](https://sentry.io/legal/dpa/)
- [Sentry subprocessors](https://sentry.io/legal/subprocessors/)
- [Sentry EU storage](https://www.sentry.help/en/articles/13964378-sentry-s-eu-region-faq)
- [Sentry retention](https://docs.sentry.io/security-legal-pii/security/data-retention-periods/)
- [GDPR text](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
