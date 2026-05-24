# RestiView — Design & Launch Support
## Statement of Work
**Client:** Peter Kern  
**Contractor:** Tara Kern  
**Date:** May 2026  
**Version:** 1.0

---

## 1. Overview

Tara Kern ("Contractor") is engaged to provide graphic design, UX review, testing, and marketing asset production services to support the public launch of the RestiView mobile application on Google Play.

RestiView is a restaurant review app for Android. Users can record and manage personal restaurant reviews, share reviews with friends, and discover nearby restaurants. The app is currently in closed beta testing and is being prepared for public release on the Google Play Store.

---

## 2. Scope of Work

---

### Task A — App Design Review & Improvements

#### A1 — Full Visual & UX Audit
**Description:**  
Review every screen in the RestiView app and document current design issues. This includes assessing colour usage, typography consistency, spacing, layout balance, button sizing, touch target sizes, and overall visual polish. The review should consider both aesthetic quality and usability — for example, whether labels are clear, whether actions are obvious, and whether the app feels professional and consistent throughout.

**Expected Output:**  
A written or annotated document (screenshots with notes, or a Figma/design tool file) listing each screen with identified issues and suggested improvements. Prioritised by impact.

---

#### A2 — Revised Colour Palette & Typography Proposal
**Description:**  
Based on the audit findings, propose a revised visual direction for the app. The current colour scheme uses dark green (`#2E4F3E`) and beige (`#F5F0E6`) as primary brand colours. The proposal should either refine these or suggest an alternative palette. Typography should be assessed — the app currently uses the Gelica font family.

The proposal should include:
- Primary, secondary, and accent colours with hex values
- Background and surface colours
- Text colours (primary, secondary, muted)
- Font pairing recommendation (or confirmation to keep Gelica)
- Recommended font sizes for headings, body, labels, buttons

**Expected Output:**  
A colour and typography specification — this can be a simple document, a Figma style guide page, or a PDF. Must include hex values for all colours so the developer can implement them directly in code.

---

#### A3 — Design Implementation Collaboration
**Description:**  
Work with the developer to implement the agreed design changes in the app. The developer will make all code changes — the Contractor's role is to review the results on the device, identify where the implementation doesn't match the proposal, and provide clear feedback until the result matches the agreed design.

**Expected Output:**  
Written sign-off that the implemented design matches the approved proposal. A before/after screenshot comparison is helpful but optional.

---

#### A4 — Button & Component Consistency Review
**Description:**  
Review the consistency of interactive elements across the app — buttons, input fields, dropdowns, dialogs, and navigation elements. Assess whether sizes, colours, and styles are consistent. For example, are all primary action buttons the same colour? Are all destructive actions (delete, clear) visually distinct? Are touch targets large enough for comfortable use?

**Expected Output:**  
A specification document or annotated screenshots defining the intended style for each component type (primary button, secondary button, destructive button, text button, input field, etc.) so the developer can apply them consistently.

---

### Task B — App Testing

#### B1 — Structured App Walkthrough
**Description:**  
Test the app by working through all main user flows:
- Registration and sign-in
- Adding a new restaurant review (general info, ratings, comments, photos)
- Editing and deleting a review
- Viewing the review list and filtering/sorting
- Preview screen
- Friends — sending and receiving friend requests
- Requesting and sharing reviews between friends
- Settings screen
- Help screen

For each flow, note anything that is confusing, broken, missing, or visually inconsistent.

**Expected Output:**  
A bug and feedback log — a simple spreadsheet or document with columns for: Screen, Issue Description, Severity (High/Medium/Low), Suggested Fix.

---

#### B2 — Retest After Fixes
**Description:**  
After the developer has addressed the issues found in B1, retest the affected areas to confirm fixes are working correctly and no new issues have been introduced.

**Expected Output:**  
Updated bug log with each issue marked as Resolved, Partially Fixed, or Still Outstanding.

---

### Task C — Play Store Launch Assets

#### C1 — App Icon
**Description:**  
Design a polished app icon for the Google Play Store. The icon must work at small sizes (as small as 48×48 on a device home screen) as well as large (512×512 on the Play Store listing). It should be visually distinctive, recognisable, and reflect the restaurant review theme of the app.

Requirements:
- Delivered as 512×512 PNG with transparent or solid background
- Must comply with Google Play icon guidelines (no rounded corners applied by designer — Android applies these automatically)
- Also deliver an adaptive icon version: foreground layer and background layer separately (for use as the Android launcher icon)

**Expected Output:**  
- `icon_512.png` (512×512, Play Store upload)
- `icon_foreground.png` (adaptive icon foreground layer, 108×108dp safe zone)
- `icon_background.png` (adaptive icon background layer)
- Source file (Figma, Illustrator, or equivalent)

---

#### C2 — Feature Graphic
**Description:**  
Design the feature graphic shown at the top of the Play Store listing page. This is a banner-style image that introduces the app visually. It should include the app name "RestiView", a tagline or short description, and visual elements that communicate what the app does. It must not include device frames or screenshots (Google prohibits this in the feature graphic).

Requirements:
- Size: 1024×500 pixels
- JPG or PNG
- Should look good on both light and dark Play Store themes

**Expected Output:**  
- `feature_graphic.png` (1024×500)
- Source file

---

#### C3 — Short Description (Play Store)
**Description:**  
Write the short description for the Play Store listing. This appears below the app name in search results and on the listing page. It must be punchy, clear, and within 80 characters. It should communicate what the app does and why someone would want it.

**Expected Output:**  
One or two alternative short description options (80 characters max each) for Peter to choose from.

---

#### C4 — Full Description (Play Store)
**Description:**  
Write the full app description for the Play Store listing (up to 4000 characters). This should explain what RestiView does, list key features, and be written in a way that is both engaging to a human reader and discoverable via Play Store search (naturally include relevant keywords like "restaurant review", "dining", "food diary", etc.).

Structure suggestion:
- Opening hook (1-2 sentences)
- What is RestiView? (short paragraph)
- Key features (bullet list)
- Who is it for? (short paragraph)
- Call to action

**Expected Output:**  
A draft full description ready to paste into Play Console, in plain text. Include keyword suggestions used.

---

### Task D — Website Update

**Note:** The RestiView website ([restiview.com](https://restiview.com)) is hosted on Yola and managed via their SiteBuilder tool. No coding is required — all changes are made through the visual editor. The Privacy Policy page is already complete and does not need updating.

#### D1 — Content & Design Audit
**Description:**  
Review the current website and document what needs to be updated or improved. Consider: Is the content current and accurate? Does the visual design match the updated app design? Is the call-to-action (download the app) clear and prominent? Are there any missing pages?

**Expected Output:**  
A short written list of recommended changes, prioritised.

---

#### D2 — Website Content Update
**Description:**  
Using the Yola SiteBuilder, update the website content to reflect the current state of the app. This includes:
- Updating text descriptions to match the current feature set
- Replacing any outdated screenshots with current ones
- Adding the Play Store download badge and link once the app is publicly live
- Ensuring the app icon and feature graphic are used consistently
- Adding a Terms & Conditions page (required for Apple App Store submission later)

**Expected Output:**  
Updated live website with all changes published.

---

## 3. Out of Scope
- App development or code changes (developer responsibility)
- Play Store or Firebase account management
- Social media account creation or ongoing management
- Paid advertising or marketing campaigns
- Apple App Store assets (to be addressed in a future phase)

---

## 4. Deliverables Summary

| Ref | Deliverable | Format |
|---|---|---|
| A1 | Design audit document | PDF / annotated screenshots |
| A2 | Colour & typography specification | PDF / Figma |
| A3 | Design sign-off | Written confirmation |
| A4 | Component style specification | PDF / annotated screenshots |
| B1 | Bug & feedback log | Spreadsheet / document |
| B2 | Updated bug log | Spreadsheet / document |
| C1 | App icon files | PNG + source |
| C2 | Feature graphic | PNG + source |
| C3 | Short description options | Plain text |
| C4 | Full Play Store description | Plain text |
| D1 | Website audit | Written list |
| D2 | Updated live website | Published on restiview.com |

---

## 5. Estimated Effort

| Area | Hours |
|---|---|
| A — App design review & improvements | 18h |
| B — App testing | 7h |
| C — Play Store assets | 8h |
| D — Website update | 6h |
| **Total** | **39h** |

---

## 6. Suggested Priority Order

1. **C1, C2** — App icon and feature graphic (needed for Play Store listing immediately)
2. **C3, C4** — Store descriptions (needed for Play Store listing)
3. **A1, A2** — Design audit and proposal (feeds into A3, A4)
4. **B1** — App testing (can run concurrently with design work)
5. **D2** — Website update (once app is live)

---

## 7. Further Tasks to Consider

The following items are not in scope for this engagement but may be worth addressing before or after launch:

- **Onboarding screens** — A 2-3 slide welcome/tutorial shown on first launch explaining what the app does, helping new users get started without confusion
- **App preview video** — A 15-30 second screen recording with captions showing the app in use; significantly boosts Play Store conversion rates
- **Apple App Store assets** — Equivalent icons, screenshots (different sizes), and descriptions for the iOS release (future phase)
- **Support / FAQ page** — Both app stores ask for a support URL; a simple FAQ page on the website would satisfy this and reduce support queries
- **Social media presence** — A dedicated Facebook or Instagram page for RestiView to direct users to for updates and support
- **App Store Optimisation (ASO)** — Ongoing keyword research and description tuning to improve Play Store search ranking after launch
- **Social media announcement graphics** — Square (1080×1080) and landscape (1200×628) graphics for Facebook, Instagram, and X/Twitter announcing the launch
- **Launch email** — A short friendly email Peter can send to his contacts with a description, graphic, and Play Store link
- **Press kit** — A one-page PDF with app name, icon, short description, key screenshots, and Play Store link; suitable for sending to bloggers or local press

---

## 8. Compensation

Each section is priced on a fixed-price basis. Payment is due on completion and acceptance of all deliverables within that section.

| Section | Description | Fixed Price |
|---|---|---|
| A | App Design Review & Improvements | £170 |
| B | App Testing | £70 |
| C | Play Store Launch Assets | £70 |
| D | Website Update | £60 |
| **Total** | | **£370** |

---

*Document prepared May 2026*
