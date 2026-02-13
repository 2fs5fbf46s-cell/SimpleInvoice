import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct WebsiteCustomizationView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var profile: BusinessProfile?
    @State private var business: Business?
    @State private var draft: PublishedBusinessSite?

    @State private var isPublishing = false
    @State private var showPreviewSafari = false
    @State private var previewURL: URL?

    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var route: WebsiteRoute?
    @State private var showServicesSheet = false
    @State private var showAboutSheet = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    appNameCard
                    Divider().padding(.horizontal, 12)

                    if draft != nil {
                        rowButton(icon: "photo", title: "Hero Image", description: "This image will be used in the first section of your website landing page") {
                            route = .hero
                        }
                        Divider().padding(.horizontal, 12)

                        rowButton(icon: "paintbrush", title: "Services", description: "Edit and manage services that your business offers. These services will be shown on landing page of your website") {
                            showServicesSheet = true
                        }
                        Divider().padding(.horizontal, 12)

                        rowButton(icon: "person", title: "About Us", description: "Add details about your business to be displayed on your website landing page") {
                            showAboutSheet = true
                        }
                        Divider().padding(.horizontal, 12)

                        rowButton(icon: "person.3", title: "Our Team", description: "Edit and manage team members to be displayed on your website landing page") {
                            route = .team
                        }
                        Divider().padding(.horizontal, 12)

                        rowButton(icon: "photo.on.rectangle", title: "Image Gallery", description: "Add multiple images of your business to be displayed on your website landing page") {
                            route = .gallery
                        }
                        Divider().padding(.horizontal, 12)
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 72)
            }
        }
        .navigationTitle("Business Customization")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveDraft()
                    alertMessage = "Saved"
                    showAlert = true
                }
                .fontWeight(.semibold)
                .foregroundStyle(SBWTheme.brandBlue)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let draft {
                HStack(spacing: 8) {
                    statusPill(draft.status)

                    Button("Preview Website") {
                        previewWebsite(draft: draft)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await publishWebsite(draft: draft) }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish Website")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPublishing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showPreviewSafari) {
            if let previewURL {
                SafariView(url: previewURL) {
                    showPreviewSafari = false
                }
            }
        }
        .alert("Website", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "Something went wrong.")
        }
        .onAppear {
            loadContext()
        }
        .navigationDestination(item: $route) { target in
            guard let draft else { return AnyView(EmptyView()) }
            switch target {
            case .hero:
                return AnyView(WebsiteHeroImageView(draft: draft, onSave: saveDraft))
            case .team:
                return AnyView(WebsiteTeamView(draft: draft, onSave: saveDraft))
            case .gallery:
                return AnyView(WebsiteGalleryView(draft: draft, onSave: saveDraft))
            case .services, .about:
                return AnyView(EmptyView())
            }
        }
        .sheet(isPresented: $showServicesSheet) {
            if let draft {
                NavigationStack {
                    WebsiteServicesView(
                        draftID: draft.id,
                        seedServices: draft.services
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showServicesSheet = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            if let draft {
                NavigationStack {
                    WebsiteAboutView(
                        draftID: draft.id,
                        seedAboutText: draft.aboutUs,
                        seedAboutImagePath: draft.aboutImageLocalPath
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showAboutSheet = false }
                        }
                    }
                }
            }
        }
    }

    private var appNameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "at")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("App Name")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SBWTheme.brandBlue)

                    Text("Will be used as the unique app name to identify your website")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))

                    Text("App Name")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                        .padding(.top, 4)

                    TextField("App Name", text: Binding(
                        get: { draft?.handle ?? "" },
                        set: { value in
                            draft?.handle = PublishedBusinessSite.normalizeHandle(value)
                            saveDraft()
                        }
                    ))
                    .font(.system(size: 16, weight: .regular))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.bottom, 4)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func rowButton(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SBWTheme.brandBlue)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBWTheme.brandBlue)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ status: PublishStatus) -> some View {
        let color: Color
        let text: String
        switch status {
        case .draft:
            color = .secondary
            text = "Draft"
        case .queued:
            color = .orange
            text = "Queued"
        case .publishing:
            color = SBWTheme.brandBlue
            text = "Publishing"
        case .published:
            color = SBWTheme.brandGreen
            text = "Published"
        case .error:
            color = .red
            text = "Error"
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadContext() {
        do { try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext) } catch {}
        guard let businessID = activeBiz.activeBusinessID else { return }

        if let existingProfile = profiles.first(where: { $0.businessID == businessID }) {
            self.profile = existingProfile
        } else {
            let created = BusinessProfile(businessID: businessID)
            modelContext.insert(created)
            try? modelContext.save()
            self.profile = created
        }

        self.business = businesses.first(where: { $0.id == businessID }) ?? businesses.first

        guard let profile else { return }
        let draft = BusinessSitePublishService.shared.draft(for: businessID, context: modelContext)

        if draft.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let businessName = business?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            draft.appName = businessName.isEmpty ? profile.name : businessName
        }
        if draft.handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.handle = PublishedBusinessSite.normalizeHandle(profile.name)
        }
        if draft.services.isEmpty {
            draft.services = PublishedBusinessSite.splitLines(profile.catalogCategoriesText)
        }
        if draft.aboutUs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.aboutUs = profile.defaultThankYou.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
        self.draft = draft
    }

    private func saveDraft() {
        guard let draft else { return }
        BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
    }

    private func previewWebsite(draft: PublishedBusinessSite) {
        let normalized = PublishedBusinessSite.normalizeHandle(draft.handle)
        guard !normalized.isEmpty else {
            alertMessage = "Add a website handle before previewing."
            showAlert = true
            return
        }

        draft.handle = normalized
        saveDraft()
        previewURL = PortalBackend.shared.publicSiteURL(handle: normalized)
        showPreviewSafari = true
    }

    @MainActor
    private func publishWebsite(draft: PublishedBusinessSite) async {
        guard let profile else { return }
        isPublishing = true
        defer { isPublishing = false }

        do {
            try await BusinessSitePublishService.shared.queuePublish(
                draft: draft,
                profile: profile,
                business: business,
                context: modelContext
            )
            alertMessage = "Website queued for publishing."
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

private enum WebsiteRoute: String, Identifiable {
    case hero
    case services
    case about
    case team
    case gallery

    var id: String { rawValue }
}

private struct WebsiteHeroImageView: View {
    let draft: PublishedBusinessSite
    let onSave: () -> Void

    @State private var selectedHeroItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                pageDescription("This image will be used in the first section of your website landing page")
                SectionTitle(icon: "photo", text: "Hero Image")

                PhotosPicker(selection: $selectedHeroItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 220)

                        if let path = draft.heroImageLocalPath,
                           let image = UIImage(contentsOfFile: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 220)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.square")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.secondary.opacity(0.55))
                                Text("Add Image")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.secondary.opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)

                Divider().padding(.top, 16)
                Spacer()
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
        .navigationTitle("Hero Image")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedHeroItem) { _, newValue in
            Task {
                guard let newValue,
                      let data = try? await newValue.loadTransferable(type: Data.self),
                      let path = try? writeTemporaryImage(data: data, prefix: "public-site-hero") else { return }
                await MainActor.run {
                    draft.heroImageLocalPath = path
                    draft.heroImageRemoteUrl = nil
                    onSave()
                }
            }
        }
    }
}

private struct WebsiteServicesView: View {
    @Environment(\.modelContext) private var modelContext
    let draftID: UUID
    let seedServices: [String]

    @State private var rows: [ServiceRow] = []
    @State private var didLoad = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageDescription("Edit and manage services that your business offers. These services will be shown on landing page of your website")

                    ForEach(rows.indices, id: \.self) { idx in
                        serviceBlock(index: idx)
                        Divider().padding(.horizontal, 12)
                    }

                    Button {
                        rows.append(ServiceRow())
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Add Service")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(SBWTheme.brandBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.86, green: 0.90, blue: 0.98))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { persistRows() }
                    .fontWeight(.semibold)
                    .foregroundStyle(SBWTheme.brandBlue)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadRows()
        }
        .onDisappear { persistRows() }
    }

    private func serviceBlock(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(icon: "paintbrush", text: "Service # \(index + 1)")
                Spacer()
                if rows.count > 1 {
                    Button(role: .destructive) {
                        rows.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 18, weight: .regular))
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 14)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Service Name", text: Binding(
                    get: { rows[index].name },
                    set: { rows[index].name = String($0.prefix(15)) }
                ))
                .font(.system(size: 16))
                Underline()
                HStack { Spacer(); Text("\(rows[index].name.count) / 15").foregroundStyle(.secondary).font(.system(size: 10)) }

                TextField("Service Detail", text: Binding(
                    get: { rows[index].detail },
                    set: { rows[index].detail = String($0.prefix(120)) }
                ))
                .font(.system(size: 16))
                Underline()
                HStack { Spacer(); Text("\(rows[index].detail.count) / 120").foregroundStyle(.secondary).font(.system(size: 10)) }
            }
            .padding(.leading, 32)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
    }

    private func loadRows() {
        let parsed = seedServices.map { ServiceRow.parse($0) }
        rows = parsed.isEmpty ? [ServiceRow()] : parsed
    }

    private func persistRows() {
        guard let draft = fetchPublishedBusinessSite(id: draftID, context: modelContext) else { return }
        draft.services = rows
            .map { $0.combined }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
    }

    private struct ServiceRow {
        var name: String = ""
        var detail: String = ""

        var combined: String {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { return d }
            if d.isEmpty { return n }
            return "\(n) - \(d)"
        }

        static func parse(_ raw: String) -> ServiceRow {
            let parts = raw.split(separator: "-", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 { return ServiceRow(name: String(parts[0].prefix(15)), detail: String(parts[1].prefix(120))) }
            return ServiceRow(name: String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(15)), detail: "")
        }

    }
}

private struct WebsiteAboutView: View {
    @Environment(\.modelContext) private var modelContext
    let draftID: UUID
    let seedAboutText: String
    let seedAboutImagePath: String?

    @State private var selectedImageItem: PhotosPickerItem?
    @State private var aboutText: String = ""
    @State private var aboutImagePath: String?
    @State private var didLoad = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                pageDescription("Add details about your business to be displayed on your website landing page")

                SectionTitle(icon: "photo", text: "About Us - Image")
                PhotosPicker(selection: $selectedImageItem, matching: .images, photoLibrary: .shared()) {
                    ImageDropTile(path: aboutImagePath)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                .buttonStyle(.plain)

                Divider().padding(.top, 16)
                SectionTitle(icon: "doc.text", text: "About Us - Description")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Description", text: Binding(
                        get: { aboutText },
                        set: { aboutText = String($0.prefix(600)) }
                    ))
                    .font(.system(size: 16))
                    Underline()

                    HStack {
                        Spacer()
                        Text("\(aboutText.count) / 600")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                    }
                }
                .padding(.leading, 32)
                .padding(.trailing, 12)
                .padding(.bottom, 16)

                Divider()
                Spacer()
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
        .navigationTitle("About Us")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    persist()
                }
                .fontWeight(.semibold)
                .foregroundStyle(SBWTheme.brandBlue)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            aboutText = seedAboutText
            aboutImagePath = seedAboutImagePath
        }
        .onDisappear {
            persist()
        }
        .onChange(of: selectedImageItem) { _, newValue in
            Task {
                guard let newValue,
                      let data = try? await newValue.loadTransferable(type: Data.self),
                      let path = try? writeTemporaryImage(data: data, prefix: "public-site-about") else { return }
                await MainActor.run {
                    guard let draft = fetchPublishedBusinessSite(id: draftID, context: modelContext) else { return }
                    draft.aboutImageLocalPath = path
                    draft.aboutImageRemoteUrl = nil
                    BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
                    aboutImagePath = path
                }
            }
        }
    }

    private func persist() {
        guard let draft = fetchPublishedBusinessSite(id: draftID, context: modelContext) else { return }
        draft.aboutUs = aboutText
        BusinessSitePublishService.shared.saveDraftEdits(draft, context: modelContext)
    }
}

private struct WebsiteTeamView: View {
    let draft: PublishedBusinessSite
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var didLoad = false

    // V2 draft array (THIS is what we edit)
    @State private var draftMembers: [PublishedBusinessSite.TeamMemberV2] = []

    // Per-member PhotosPicker selection
    @State private var pickerSelection: [String: PhotosPickerItem?] = [:]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        pageDescription("Edit and manage team members to be displayed on your website landing page")

                        if draftMembers.isEmpty {
                            Text("No Team Member Added")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                                .padding(.bottom, 10)
                        } else {
                            ForEach(draftMembers.indices, id: \.self) { idx in
                                teamMemberBlock(index: idx)
                                Divider().padding(.horizontal, 12)
                            }
                        }

                        Button {
                            let new = PublishedBusinessSite.TeamMemberV2()
                            draftMembers.append(new)
                            persistToModel()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(new.id, anchor: .top)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .regular))
                                Text("Add Team Member")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .foregroundStyle(SBWTheme.brandBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.86, green: 0.90, blue: 0.98))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)

                        Spacer(minLength: 24)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("Our Team")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    persistToModel()
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundStyle(SBWTheme.brandBlue)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true

            // If V2 is empty, migrate legacy names once.
            draft.migrateLegacyTeamMembersIfNeeded()

            // Load V2 list into local draft array
            draftMembers = draft.teamMembersV2

            // Ensure at least 1 row if you want (optional)
            // if draftMembers.isEmpty { draftMembers = [PublishedBusinessSite.TeamMemberV2()] }
        }
        .onDisappear {
            persistToModel()
        }
    }

    private func teamMemberBlock(index: Int) -> some View {
        guard draftMembers.indices.contains(index) else { return AnyView(EmptyView()) }
        let memberId = draftMembers[index].id

        let photoPath = draft.teamPhotoLocalPathById[memberId]
        let selectedPicker = Binding<PhotosPickerItem?>(
            get: { pickerSelection[memberId] ?? nil },
            set: { pickerSelection[memberId] = $0 }
        )

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(icon: "person", text: "Team Member # \(index + 1)")
                    Spacer()
                    Button(role: .destructive) {
                        if draftMembers.indices.contains(index) {
                            let removed = draftMembers[index].id
                            draftMembers.remove(at: index)
                            pickerSelection.removeValue(forKey: removed)

                            // remove stored photo local path too
                            var map = draft.teamPhotoLocalPathById
                            map.removeValue(forKey: removed)
                            draft.teamPhotoLocalPathById = map

                            persistToModel()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(8)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 10)
                }

                PhotosPicker(selection: selectedPicker, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 140)

                        if let photoPath,
                           let image = UIImage(contentsOfFile: photoPath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.square")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.secondary.opacity(0.55))
                                Text("Add Photo")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.secondary.opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .onChange(of: pickerSelection[memberId] ?? nil) { _, newValue in
                    Task {
                        guard let newValue,
                              let data = try? await newValue.loadTransferable(type: Data.self),
                              let path = try? writeTemporaryImage(data: data, prefix: "public-site-team")
                        else { return }

                        await MainActor.run {
                            // Store local path in the model map keyed by memberId
                            var map = draft.teamPhotoLocalPathById
                            map[memberId] = path
                            draft.teamPhotoLocalPathById = map

                            // photoUrl stays nil until publish uploads it
                            draftMembers[index].photoUrl = nil

                            persistToModel()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Your full name", text: Binding(
                        get: { draftMembers[index].name },
                        set: {
                            draftMembers[index].name = String($0.prefix(35))
                            persistToModel()
                        }
                    ))
                    .font(.system(size: 16))
                    Underline()
                    HStack {
                        Spacer()
                        Text("\(draftMembers[index].name.count) / 35")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                    }

                    Text("Work Title")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Work title", text: Binding(
                        get: { draftMembers[index].title },
                        set: {
                            draftMembers[index].title = String($0.prefix(35))
                            persistToModel()
                        }
                    ))
                    .font(.system(size: 16))
                    Underline()
                    HStack {
                        Spacer()
                        Text("\(draftMembers[index].title.count) / 35")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .id(memberId)
            .padding(.top, 8)
        )
    }

    private func persistToModel() {
        // 1) Write V2 JSON-backed array (the real source of truth)
        draft.teamMembersV2 = draftMembers

        // 2) Keep legacy list in sync for back-compat rendering (names only)
        draft.teamMembers = draftMembers
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 3) Mark dirty so publisher runs
        draft.updatedAt = Date()
        draft.needsSync = true

        // 4) Save via the existing pipeline
        onSave()
    }
}

    

private struct WebsiteGalleryView: View {
    let draft: PublishedBusinessSite
    let onSave: () -> Void

    @State private var selectedGalleryItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                pageDescription("Add multiple images of your business to be displayed on your website landing page")

                if draft.galleryLocalPaths.isEmpty {
                    Text("No Image Added")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Array(draft.galleryLocalPaths.enumerated()), id: \.offset) { idx, path in
                                ZStack(alignment: .topTrailing) {
                                    if let image = UIImage(contentsOfFile: path) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 100)
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }

                                    Button(role: .destructive) {
                                        draft.galleryLocalPaths.remove(at: idx)
                                        if idx < draft.galleryRemoteUrls.count {
                                            draft.galleryRemoteUrls.remove(at: idx)
                                        }
                                        onSave()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(6)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    }
                }

                PhotosPicker(selection: $selectedGalleryItems, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .regular))
                        Text("Add Image")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(SBWTheme.brandBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.86, green: 0.90, blue: 0.98))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 32)

                Spacer()
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
        .navigationTitle("Image Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedGalleryItems) { _, items in
            Task {
                guard !items.isEmpty else { return }
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let path = try? writeTemporaryImage(data: data, prefix: "public-site-gallery") else { continue }
                    await MainActor.run {
                        draft.galleryLocalPaths.append(path)
                    }
                }
                await MainActor.run {
                    draft.galleryRemoteUrls = []
                    onSave()
                    selectedGalleryItems = []
                }
            }
        }
    }
}

private func pageDescription(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 12)
}

private struct SectionTitle: View {
    let icon: String
    let text: String

    var body: some View {
    HStack(spacing: 8) {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 24)
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(SBWTheme.brandBlue)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    }
}

private struct ImageDropTile: View {
    let path: String?

    var body: some View {
    ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(height: 180)

        if let path,
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "plus.square")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                Text("Add Image")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
        }
    }
    }
}

private struct Underline: View {
    var body: some View {
    Rectangle()
        .fill(Color.secondary.opacity(0.7))
        .frame(height: 1)
    }
}

private func writeTemporaryImage(data: Data, prefix: String) throws -> String {
    let fileName = "\(prefix)-\(UUID().uuidString).jpg"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    try data.write(to: url, options: .atomic)
    return url.path
}

private func fetchPublishedBusinessSite(id: UUID, context: ModelContext) -> PublishedBusinessSite? {
    let all = (try? context.fetch(FetchDescriptor<PublishedBusinessSite>())) ?? []
    return all.first(where: { $0.id == id })
}
