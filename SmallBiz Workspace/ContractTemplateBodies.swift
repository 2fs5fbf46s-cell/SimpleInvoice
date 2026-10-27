//
//  ContractTemplateBodies.swift
//  SmallBiz Workspace
//

import Foundation

/// The built-in agreements (template v3), laid out like the founder's own
/// production agreement: Key Terms at a Glance, numbered articles, the
/// cancellation tiers with what each costs, a signature page with a
/// Provider Use Only box, and Exhibit A for the details confirmed later.
///
/// Written in the light markup `ContractDocument` reads: `# ` title,
/// `_…_` subtitle, `## ` heading, `| … |` table rows (a `|---|` row under
/// the first makes it a header), `1.1 Lead-in.` clauses, `(a)` items,
/// `[[PAGE BREAK]]` and `[[SIGNATURES]]`. It still reads as plain text in
/// the editor and the portal's text view.
///
/// Exhibit A cells are left empty on purpose: "[add …]" blanks would block
/// sending, and these are filled in by both parties after signing.
extension ContractTemplateSeeder {

    // MARK: - Templates

    static func generalAgreement() -> String {
        """
        # SERVICE AGREEMENT
        _{{Contract.Subtitle}}_

        This Service Agreement (the “Agreement”) is entered into as of the date of the last signature below (the “Effective Date”) by and between {{Business.Name}} (“Provider”) and {{Client.Name}} (“Client”). Provider and Client are each a “Party” and together the “Parties.”

        Provider will perform the services described below for a total fee of {{Invoice.Total}}. The service date is reserved only once Provider has received this Agreement signed by Client and any deposit due at signing.

        \(keyTerms(dateLabel: "Service Date", placeLabel: "Site"))

        ## ARTICLE 1 — PARTIES AND PROJECT
        1.1 Provider. {{Business.Name}}, an independent service provider, who will furnish the labor, materials, and services described in this Agreement.
        1.2 Client. {{Client.Name}}. The individual signing this Agreement on Client’s behalf represents that they are authorized to bind Client to its terms.
        1.3 Project. The work shall be performed on the Service Date at the Site shown in Key Terms at a Glance. The project name is set out in Exhibit A.
        1.4 Work Times. Start and expected completion times shall be confirmed by the Parties in writing using Exhibit A. All times in this Agreement are local to the Site.

        ## ARTICLE 2 — SCOPE OF SERVICES
        2.1 Services. Provider shall perform the following:
        {{Invoice.Items}}
        {{Job.Measurements}}
        2.2 Materials and Personnel. Provider shall furnish the tools, materials, and qualified personnel reasonably necessary to complete the services in Section 2.1, unless Exhibit A says Client will supply a material.
        2.3 Exclusions. Anything not listed in Section 2.1 is excluded from this Agreement. Any excluded item may be added only under Section 3.5.
        2.4 Site Confirmation. Before work begins, the Parties shall confirm in writing, using Exhibit A, the specifications, measurements, and any utilities or approvals the work needs.
        2.5 Changes in Scope. Neither Party may materially reduce or expand the agreed scope of services without the written agreement of the other Party.

        \(feesArticle())

        ## ARTICLE 4 — SCHEDULE
        4.1 Scheduling. Start and completion times shall be coordinated and confirmed in writing far enough in advance to allow the work to be done safely and completely.
        4.2 Delays. If the work cannot proceed as scheduled because the Site is not ready or accessible, the Parties shall agree on a new time in writing.
        4.3 Completion. On completion, Provider shall remove its tools, equipment, and work debris from the Site.

        ## ARTICLE 5 — CLIENT RESPONSIBILITIES
        5.1 Site. Client shall, at no additional cost to Provider:
        (a) provide safe, timely access to the Site and parking for Provider’s vehicles and personnel;
        (b) provide a clear and safe work area;
        (c) provide access to electrical power and water where the work requires them; and
        (d) obtain any permits, landlord, or homeowners’ association approvals the work requires, unless Exhibit A says Provider will.
        5.2 On-Site Contact. Client shall name an on-site contact who can make decisions and is reachable while work is underway.
        5.3 Communication. Client shall promptly tell Provider about any Site rules, hazards, or changes to the schedule.

        \(providerArticle(standard: "generally accepted standards for the trade"))

        ## ARTICLE 7 — PROPERTY, SAFETY, AND DAMAGE
        7.1 Tools and Equipment. Provider retains ownership of all tools and equipment it brings to the Site.
        7.2 Safe Work. Provider is responsible for performing the work safely and for keeping its work area reasonably tidy.
        7.3 Responsibility for Damage. Each Party is responsible for loss or damage caused by its own negligence or willful misconduct, or that of its employees, agents, or guests. Provider is not responsible for pre-existing conditions it did not cause.
        7.4 Safety Pause. Provider may pause any affected work when an immediate safety hazard exists. Provider shall notify Client promptly and cooperate in good faith to resume as quickly as possible.

        \(cancellationArticle(noun: "the Service Date", dateNoun: "the Service Date"))

        \(closingArticles())

        \(signaturePage())

        [[PAGE BREAK]]
        # EXHIBIT A
        _PROJECT DETAILS AND CONFIRMATION_

        This Exhibit records the project details to be confirmed under Sections 1.4, 2.4, and 4.1. Once completed and initialed by both Parties in the footer below (or confirmed by email), it forms part of this Agreement.

        ## Part 1 — Project Details
        | Item | Details |
        |---|---|
        | Project Name |  |
        | Start Time |  |
        | Expected Completion |  |
        | On-Site Contact / Phone |  |
        | Access / Parking Instructions |  |
        | Final Balance Deadline | {{Terms.BalanceDeadline}} |

        ## Part 2 — Specifications
        | Item | Quantity / Specification | Notes |
        |---|---|---|
        | Materials / Finishes |  |  |
        | Measurements |  |  |
        | Supplied by Client |  |  |
        | Utilities Needed (Power / Water) |  |  |
        | Permits / Approvals |  |  |
        | Other Requirements |  |  |
        """
    }

    static func photographyAgreement() -> String {
        """
        # PHOTOGRAPHY SERVICES AGREEMENT
        _{{Contract.Subtitle}}_

        This Photography Services Agreement (the “Agreement”) is entered into as of the date of the last signature below (the “Effective Date”) by and between {{Business.Name}} (“Provider”) and {{Client.Name}} (“Client”). Provider and Client are each a “Party” and together the “Parties.”

        Provider will photograph the Event described below and deliver edited images for a total fee of {{Invoice.Total}}. The Event date is reserved only once Provider has received this Agreement signed by Client and any deposit due at signing.

        \(keyTerms(dateLabel: "Event Date", placeLabel: "Venue"))

        \(eventPartiesArticle(trade: "photography"))

        ## ARTICLE 2 — SCOPE OF SERVICES
        2.1 Services. Provider shall provide the following:
        {{Invoice.Items}}
        2.2 Coverage. Coverage begins and ends at the times confirmed in Exhibit A. Coverage beyond those times is an additional service under Section 3.5.
        2.3 Equipment. Provider shall use professional camera equipment in good working order, with backup cameras and memory cards for the Event.
        2.4 Deliverables. Provider shall deliver professionally edited images digitally, through an online gallery or download link, by the delivery date in Exhibit A. Unedited and RAW files are not included.
        2.5 Exclusions. Video, prints, albums, and additional photographers are not included unless listed in Section 2.1.
        2.6 Shot List. Client may give Provider a shot list and the names of key people before the Event, using Exhibit A. Provider will make reasonable efforts to capture it, but cannot guarantee any particular image.
        2.7 Changes in Scope. Neither Party may materially reduce or expand the agreed scope of services without the written agreement of the other Party.

        \(feesArticle())

        ## ARTICLE 4 — SCHEDULE
        4.1 Scheduling. The Event timeline, arrival time, and any additional locations shall be confirmed in writing in advance of the Event using Exhibit A.
        4.2 Delays. If the Event runs late for reasons outside Provider’s control, coverage beyond the confirmed end time is an additional service under Section 3.5, if Provider is available.
        4.3 Meals and Breaks. For coverage of six (6) hours or more, Client shall allow Provider a reasonable meal break.

        ## ARTICLE 5 — CLIENT RESPONSIBILITIES
        5.1 Venue. Client shall, at no additional cost to Provider:
        (a) secure any permissions needed for photography at the Venue, and tell Provider of any Venue restrictions on photography;
        (b) provide timely access and parking for Provider; and
        (c) make key people available at the times in the Event timeline.
        5.2 On-Site Contact. Client shall name an on-site contact who knows the Event timeline and can point out key people.
        5.3 Guest Photography. Provider is not responsible for images missed because of guests’ cameras or phones, Venue restrictions, or lighting conditions at the Venue.

        \(providerArticle(standard: "generally accepted standards for professional event photography"))

        ## ARTICLE 7 — DELIVERY, COPYRIGHT, AND USAGE
        7.1 Copyright. Provider retains the copyright in all images created under this Agreement.
        7.2 Client License. Client receives a license to use the delivered images for personal use, including sharing them online with credit to Provider where practical. Commercial use, resale, or editing that changes an image requires Provider’s written permission.
        7.3 Portfolio Use. Provider may use images from the Event in its portfolio and marketing unless Client asks otherwise in writing before the Event.
        7.4 Selection and Editing. Image selection and editing are made in Provider’s professional judgment.
        7.5 Archive. Provider shall keep a backup of the delivered images for at least ninety (90) days after delivery.

        \(cancellationArticle(noun: "the Event", dateNoun: "the Event date"))

        \(closingArticles())

        \(signaturePage())

        [[PAGE BREAK]]
        # EXHIBIT A
        _EVENT DETAILS AND COVERAGE CONFIRMATION_

        This Exhibit records the Event details and coverage to be confirmed under Sections 1.4, 2.2, 2.6, and 4.1. Once completed and initialed by both Parties in the footer below (or confirmed by email), it forms part of this Agreement.

        ## Part 1 — Event Details
        | Item | Details |
        |---|---|
        | Event Name |  |
        | Coverage Start Time |  |
        | Coverage End Time |  |
        | Additional Locations |  |
        | On-Site Contact / Phone |  |
        | Parking / Arrival Instructions |  |
        | Final Balance Deadline | {{Terms.BalanceDeadline}} |

        ## Part 2 — Coverage and Deliverables
        | Item | Details | Notes |
        |---|---|---|
        | Shot List |  | Attached ☐ |
        | Key People / Family Groups |  |  |
        | Second Photographer |  |  |
        | Number of Edited Images |  |  |
        | Gallery Delivery Date |  |  |
        | Prints / Albums |  |  |
        | Other Requirements |  |  |
        """
    }

    static func djAgreement() -> String {
        """
        # DJ SERVICES AGREEMENT
        _{{Contract.Subtitle}}_

        This DJ Services Agreement (the “Agreement”) is entered into as of the date of the last signature below (the “Effective Date”) by and between {{Business.Name}} (“Provider”) and {{Client.Name}} (“Client”). Provider and Client are each a “Party” and together the “Parties.”

        Provider will furnish professional DJ services, sound equipment, and an operator for the Event described below for a total fee of {{Invoice.Total}}. The Event date is reserved only once Provider has received this Agreement signed by Client and any deposit due at signing.

        \(keyTerms(dateLabel: "Event Date", placeLabel: "Venue"))

        \(eventPartiesArticle(trade: "DJ and entertainment"))

        ## ARTICLE 2 — SCOPE OF SERVICES
        2.1 Services. Provider shall provide the following:
        {{Invoice.Items}}
        2.2 Equipment. Provider shall furnish the sound equipment reasonably necessary for the Event, including:
        (a) a professional sound system and amplifiers suited to the Venue;
        (b) DJ mixing and playback equipment, with backup playback;
        (c) microphones and all required audio cabling; and
        (d) speaker stands and a DJ table.
        2.3 Personnel. Provider shall furnish a qualified DJ for the agreed Event times, and any assistant needed to set up and run the equipment safely.
        2.4 Included Services. The Total Fee includes equipment transportation, setup, soundcheck, performance during the confirmed Event times, breakdown, and removal of all Provider equipment from the Venue.
        2.5 Exclusions. Lighting, video, live musicians, and Venue décor are not included unless listed in Section 2.1. Any excluded item may be added only under Section 3.5.
        2.6 Music Planning. Before the Event, the Parties shall confirm in writing, using Exhibit A, must-play and do-not-play songs, special songs, announcements, and any microphone needs. Provider will make reasonable efforts to honor requests, and uses professional judgment to keep the Event on track.
        2.7 Changes in Scope. Neither Party may materially reduce or expand the agreed scope of services without the written agreement of the other Party.

        \(feesArticle())

        ## ARTICLE 4 — EVENT SCHEDULE
        4.1 Scheduling. Load-in, setup, soundcheck, and Event times shall be coordinated and confirmed in writing far enough in advance to allow safe setup and complete system testing.
        4.2 Overtime. Performance beyond the confirmed end time is an additional service under Section 3.5, if Provider is available.
        4.3 Breakdown. Breakdown begins at the end of the Event. Client shall keep Provider’s access to the Venue until all Provider equipment has been removed.

        ## ARTICLE 5 — CLIENT RESPONSIBILITIES
        5.1 Venue. Client shall, at no additional cost to Provider:
        (a) secure all permissions necessary for Provider’s use of the Venue;
        (b) provide timely loading access and parking for Provider’s vehicles and personnel;
        (c) provide a safe, clear, and suitable area for setup and performance; and
        (d) provide properly grounded electrical power within reach of the setup area.
        5.2 On-Site Representative. Client shall name an on-site representative with decision-making authority who is available to Provider throughout the Event.
        5.3 Communication. Client shall promptly tell Provider about Venue rules, sound or volume limits, and any changes to the Event schedule.
        5.4 Performance Rights. Client is responsible for any licenses the Venue requires for the public performance of music at the Event.

        \(providerArticle(standard: "generally accepted standards for professional event DJ services"))

        ## ARTICLE 7 — EQUIPMENT, SAFETY, AND DAMAGE
        7.1 Ownership and Control. Provider retains full ownership and operational control of all equipment it furnishes.
        7.2 Equipment Protection. Client shall make reasonable efforts to prevent unauthorized use of Provider’s equipment and to keep food, beverages, and guests away from equipment and cable runs.
        7.3 Safe Installation. Provider is responsible for the safe installation of its equipment, cable management, and safe operation of the sound system.
        7.4 Responsibility for Damage. Each Party is responsible for loss or damage caused by its own negligence or willful misconduct, or that of its employees, agents, or guests. Client is not responsible for ordinary wear and tear or for damage caused by Provider’s personnel.
        7.5 Safety Pause. Provider may pause performance when an immediate safety hazard exists, including guest conduct that threatens people or equipment. Provider shall notify Client promptly and cooperate in good faith to resume as quickly as possible.

        \(cancellationArticle(noun: "the Event", dateNoun: "the Event date"))

        \(closingArticles())

        \(signaturePage())

        [[PAGE BREAK]]
        # EXHIBIT A
        _EVENT DETAILS AND MUSIC CONFIRMATION_

        This Exhibit records the Event details and music plan to be confirmed under Sections 1.4, 2.6, and 4.1. Once completed and initialed by both Parties in the footer below (or confirmed by email), it forms part of this Agreement.

        ## Part 1 — Event Details
        | Item | Details |
        |---|---|
        | Event Name |  |
        | Load-In Time |  |
        | Soundcheck Time |  |
        | Doors / Event Start Time |  |
        | Anticipated Event End Time |  |
        | On-Site Representative / Phone |  |
        | Loading / Parking Instructions |  |
        | Final Balance Deadline | {{Terms.BalanceDeadline}} |

        ## Part 2 — Music and Technical Requirements
        | Requirement | Details | Notes |
        |---|---|---|
        | Must-Play Songs |  | List attached ☐ |
        | Do-Not-Play Songs |  |  |
        | Special Songs (Entrance, First Dance, etc.) |  |  |
        | Announcements / Introductions |  |  |
        | Microphones (Wired / Wireless) |  |  |
        | Volume Limits / Venue Rules |  |  |
        | Power Locations |  |  |
        | Other Requirements |  |  |
        """
    }

    // MARK: - Shared sections

    private static func keyTerms(dateLabel: String, placeLabel: String) -> String {
        """
        ## KEY TERMS AT A GLANCE
        | Client | {{Client.NameWithContact}} |
        | Provider | {{Business.NameWithContact}} |
        | \(dateLabel) | {{Job.Day}} |
        | \(placeLabel) | {{Job.Location}} |
        | Services | {{Job.Title}} |
        | Total Fee | {{Invoice.Total}} |
        | Deposit | {{Terms.DepositLine}} |
        | Final Balance | {{Terms.BalanceLine}} |
        | Cancellation | {{Terms.CancellationSummary}} (Section 8.2) |
        """
    }

    private static func eventPartiesArticle(trade: String) -> String {
        """
        ## ARTICLE 1 — PARTIES AND EVENT
        1.1 Provider. {{Business.Name}}, an independent \(trade) provider, who will furnish the equipment, personnel, and services described in this Agreement.
        1.2 Client. {{Client.Name}}. The individual signing this Agreement on Client’s behalf represents that they are authorized to bind Client to its terms.
        1.3 Event. The Event shall take place on the Event Date at the Venue shown in Key Terms at a Glance. The Event name is set out in Exhibit A.
        1.4 Event Times. The Event start and end times shall be confirmed by the Parties in writing using Exhibit A. All times in this Agreement are local to the Venue.
        """
    }

    private static func feesArticle() -> String {
        """
        ## ARTICLE 3 — FEES AND PAYMENT
        3.1 Total Fee. Client shall pay Provider a total fee of {{Invoice.TotalWords}} (the “Total Fee”) for the services in Article 2, inclusive of any applicable taxes shown on the invoice.
        3.2 Deposit. {{Terms.DepositClause}}
        3.3 Final Balance. {{Terms.BalanceClause}}
        3.4 Payment Method. Client shall pay using a payment method listed on Provider’s invoice and shall reference the invoice number on each payment. Upon request, Provider will furnish a completed IRS Form W-9 and an invoice for each installment.
        3.5 Additional Services. No charges beyond the Total Fee shall apply unless both Parties approve the additional services and their price in writing before any related expense is incurred.
        3.6 Late Payment. If any payment is not received when due, Provider shall give Client written notice and a reasonable opportunity to pay before suspending any services. Any suspension of services shall be communicated to Client in writing before it takes effect.
        """
    }

    private static func providerArticle(standard: String) -> String {
        """
        ## ARTICLE 6 — PROVIDER RESPONSIBILITIES
        6.1 Advance Requirements. Provider shall tell Client in writing, before arrival, of its power, access, and setup requirements.
        6.2 Professional Standard. Provider shall perform all services in a professional and workmanlike manner consistent with \(standard), using equipment in good working order.
        6.3 Personnel and Conduct. Provider shall ensure that its personnel conduct themselves professionally and follow the rules of the location communicated to Provider in advance.
        6.4 Licenses and Insurance. Provider shall maintain any license or insurance the law requires for its services and will provide proof on request.
        """
    }

    /// The tiers come from `ContractTerms` (the business's defaults, or this
    /// contract's own); the engine writes each tier's fee with its amount.
    private static func cancellationArticle(noun: String, dateNoun: String) -> String {
        """
        ## ARTICLE 8 — CANCELLATION, RESCHEDULING, AND FORCE MAJEURE
        8.1 Written Notice. Any cancellation or request to reschedule must be made in writing under Article 11.
        8.2 Cancellation by Client. If Client cancels after \(dateNoun) has been reserved, Client shall owe Provider a cancellation fee set by the number of calendar days between Provider’s receipt of Client’s written notice and \(dateNoun), as follows, to the extent permitted by law:
        (a) More than {{Terms.CancelEarlyDays}} days before \(noun): {{Terms.CancelEarlyFee}}
        (b) {{Terms.CancelMidRange}} days before \(noun): {{Terms.CancelMidFee}}
        (c) {{Terms.CancelLateDays}} days or fewer before \(noun): {{Terms.CancelLateFee}}
        8.3 Reasonable Estimate. The Parties agree that these fees are a reasonable estimate of Provider’s losses from a cancellation, including the lost chance to book the date and the cost of preparation, and are not a penalty. No cancellation charge beyond Section 8.2 shall apply.
        8.4 Rescheduling. A new date requires the written agreement of both Parties and is subject to Provider’s availability. How the deposit applies, the new schedule, and any change in price must be confirmed in that written agreement.
        8.5 Cancellation by Provider. If Provider cancels for any reason within Provider’s reasonable control, Provider shall refund all payments received within fourteen (14) calendar days.
        8.6 Force Majeure — Rescheduling Within 12 Months. If circumstances beyond either Party’s reasonable control — including closure of the location, severe weather, natural disaster, public-health emergency, or governmental order — make performance on \(dateNoun) impossible or unsafe, the Parties shall work together in good faith to reschedule to a mutually agreeable date, subject to Provider’s availability. No refunds shall be issued under this Section. All payments received shall be retained by Provider and credited in full toward the rescheduled date, and this Agreement shall apply to it. The rescheduled date must fall within twelve (12) months after the original date. If it does not, the credit expires and Provider retains all payments received, with no further obligation of either Party under this Agreement.
        """
    }

    private static func closingArticles() -> String {
        """
        ## ARTICLE 9 — INDEPENDENT CONTRACTOR
        9.1 Relationship. Provider is an independent contractor. Nothing in this Agreement creates an employment, partnership, joint-venture, or agency relationship between the Parties.
        9.2 Personnel and Taxes. Provider is solely responsible for directing, supervising, and paying its personnel, and for all taxes and withholdings on Provider’s compensation under this Agreement.

        ## ARTICLE 10 — LIMITATION OF LIABILITY
        10.1 Exclusion of Indirect Damages. Neither Party shall be liable to the other for any indirect, incidental, consequential, special, or punitive damages, including lost profits or lost revenue, arising out of or relating to this Agreement.
        10.2 Cap. Except for liability arising from a Party’s gross negligence, willful misconduct, or bodily injury caused by that Party, each Party’s total liability under this Agreement shall not exceed the Total Fee.

        ## ARTICLE 11 — NOTICES
        11.1 Form of Notice. All notices, approvals, and confirmations under this Agreement shall be in writing and may be delivered by email. Notice is effective when sent to the contacts below, or to another contact a Party designates in writing.
        | Party | Notice Contact |
        |---|---|
        | Provider | {{Business.NameWithContact}} |
        | Client | {{Client.NameWithContact}} |

        ## ARTICLE 12 — GENERAL PROVISIONS
        12.1 Entire Agreement. This Agreement, together with its Exhibit and any written scope or schedule confirmations accepted by both Parties, is the entire agreement between the Parties on its subject and replaces all earlier proposals, discussions, and understandings.
        12.2 Amendments. This Agreement may be changed only in a writing approved by both Parties. Approval by email from each Party’s authorized contact satisfies this requirement.
        12.3 Governing Law and Disputes. This Agreement is governed by {{Terms.GoverningLaw}}, without regard to its conflict-of-laws rules. The Parties shall first try in good faith to resolve any dispute by direct discussion. Any dispute not resolved that way shall be brought in {{Terms.DisputeVenue}}.
        12.4 Severability. If any provision of this Agreement is held invalid or unenforceable, the remaining provisions remain in full force and effect.
        12.5 Waiver. No failure or delay by either Party in exercising any right operates as a waiver of that right.
        12.6 Assignment. Neither Party may assign this Agreement without the prior written consent of the other Party.
        12.7 Counterparts and Electronic Signatures. This Agreement may be signed in counterparts and by electronic signature, each of which is an original and all of which together are one instrument.
        12.8 Effectiveness. This Agreement takes effect when signed by both Parties. Reserving the date also requires Provider’s receipt of any deposit under Section 3.2.
        """
    }

    private static func signaturePage() -> String {
        """
        [[PAGE BREAK]]
        ## ACCEPTANCE AND SIGNATURES
        By signing below, each Party confirms that it has read and understands this Agreement and accepts the scope of services, fee and payment schedule, cancellation terms, and responsibilities set out above. Each individual signing represents that they are authorized to sign on behalf of the Party they represent.
        [[SIGNATURES]]

        ## PROVIDER USE ONLY
        Deposit received on: ____________________   Amount / Method / Ref.: ____________________
        ☐ Date reserved      Final balance received on: ____________________
        """
    }
}
