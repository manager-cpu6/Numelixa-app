# Numelixa Legal Center — Source Audit

**Scope:** Android app presentation only. No website policy text was changed.  
**Source checked:** the current Numelixa website repository's published policy pages and public footer.

## Published policies verified

| In-app label | Official route | Audit note |
|---|---|---|
| Terms of Service | `https://www.numelixa.com/terms` | Includes account security, wallet/orders, API use, prohibited activity, service availability, suspension and support contact |
| Privacy Policy | `https://www.numelixa.com/privacy` | Describes account/order/device data, use, retention, sharing, notifications, safeguards and privacy requests |
| Refund Policy | `https://www.numelixa.com/refund-policy` | Explains eligible wallet credits, completed orders, payment errors and refund review |
| Cookie Policy | `https://www.numelixa.com/cookie-policy` | Covers essential storage, optional analytics and browser choices |
| Rules & Acceptable Use | `https://www.numelixa.com/rules` | Published as Rules & Acceptable Use; no separate page titled Acceptable Use Policy was found |
| Account Deletion Policy | `https://www.numelixa.com/account-deletion` | Explains request channels, identity checks, deletion effects, records retained and confirmation |

The Android Legal Center links directly to these published pages. It does not paraphrase or silently replace the official policy text.

## Verified public contact

The website policy pages and footer publish `support@numelixa.com`. The account deletion policy instructs users to request deletion from the email associated with their account or through account settings where available.

## Owner / legal review required

1. **Company identity and jurisdiction:** the reviewed policy pages do not establish a company registration number, registered office, governing law or dispute forum. Do not add these without owner/legal confirmation.
2. **Privacy detail:** confirm controller identity, legal basis, processor categories, international transfers, retention periods by data type, data-subject request timelines and the actual handling of SMS/OTP content.
3. **Cookies and analytics:** confirm which optional analytics are currently enabled and whether the consent behavior matches deployed website tags.
4. **Refund rules:** confirm operational edge cases for provider failures, partially delivered activations, duplicate payments, pending payments and unused wallet balance.
5. **Account deletion:** confirm how outstanding balances, active activations, support tickets, audit records and developer API keys are handled; confirm a secure request workflow and response SLA.
6. **Acceptable use:** confirm that all restrictions match current provider agreements and supported use cases.
7. **Policy maintenance:** add a visible effective date/version only after the owner confirms the approved date and change history.

## App behavior and limitations

- The app provides a Legal Center index and opens the official policy route.
- No public in-app account-deletion API was verified in the backend source. The app therefore does not show a fake “Delete account now” operation.
- Users are directed to the published Account Deletion Policy and verified support address.
- This is a presentation audit, not legal advice or a legal approval.
