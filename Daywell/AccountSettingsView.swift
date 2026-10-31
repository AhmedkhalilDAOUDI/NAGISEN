import PhotosUI
import SwiftUI

/// Picture, username, bio, sign-in details, sign out and account deletion.
struct AccountSettingsView: View {
    var inSheet = false
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var bio = ""
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var confirmingDelete = false

    private var profileChanged: Bool {
        FeedRules.normalizedUsername(username) != (feed.username ?? "") ||
            bio.trimmingCharacters(in: .whitespacesAndNewlines) != feed.bio
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NagisenHeader("Account", subtitle: "How members see you.",
                              symbol: inSheet ? "xmark" : "chevron.left", onBack: { dismiss() })
                if feed.state != .ready {
                    Text("Sign in from Feed to manage your account.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                } else {
                    picture
                    profile
                    signIn
                    VStack(spacing: 14) {
                        NagisenPrimaryButton("Sign out", enabled: !feed.isBusy) {
                            Task { await feed.signOut(); dismiss() }
                        }
                        Button("Delete account", role: .destructive) { confirmingDelete = true }
                            .font(.subheadline.weight(.semibold))
                            .disabled(feed.isBusy)
                    }
                    .frame(maxWidth: .infinity)
                }
                if let message = feed.message {
                    Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            feed.message = nil
            username = feed.username ?? ""
            bio = feed.bio
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                defer { pickedPhoto = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw PostMediaError.unreadable }
                    _ = await feed.setAvatar(try PostMedia.avatar(from: data))
                } catch {
                    feed.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        .confirmationDialog("Delete your NAGISEN account?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete account and posts", role: .destructive) {
                Task { if await feed.deleteAccount() { dismiss() } }
            }
        } message: {
            Text("Your username, picture, every post, comment and photo or video you shared are removed for good. Your nutrition and workout history on this iPhone is not affected.")
        }
    }

    private var picture: some View {
        let pickerTitle = feed.avatarPath == nil ? "Add a photo" : "Change photo"
        return HStack(spacing: 18) {
            AvatarView(url: feed.avatarURL(feed.avatarPath), username: feed.username ?? "",
                       tier: feed.borderTier, size: 84)
            VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(pickerTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
                if feed.avatarPath != nil {
                    Button("Remove photo", role: .destructive) { Task { await feed.removeAvatar() } }
                        .font(.subheadline)
                }
                if feed.isBusy { ProgressView() }
            }
        }
        .softCardStyle()
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Username").foregroundStyle(Theme.muted)
                Spacer()
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 52)
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 6) {
                TextField("A line about you", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
                Text("\(bio.count)/\(FeedRules.maxBioLength)")
                    .font(.caption).foregroundStyle(bio.count > FeedRules.maxBioLength ? Theme.accentText : Theme.muted)
            }
            .padding(.vertical, 14)
            NagisenPrimaryButton("Save profile",
                                 enabled: profileChanged && !feed.isBusy &&
                                    FeedRules.isValidUsername(FeedRules.normalizedUsername(username)) &&
                                    bio.count <= FeedRules.maxBioLength) {
                Task { _ = await feed.updateProfile(username: username, bio: bio) }
            }
        }
        .font(.body)
        .softCardStyle()
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SIGN-IN")
                .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
            if let email = feed.email {
                Text(email).font(.subheadline)
            }
            HStack {
                TextField("New email", text: $newEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Change") {
                    Task { if await feed.changeEmail(to: newEmail) { newEmail = "" } }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .disabled(!newEmail.contains("@") || feed.isBusy)
            }
            .frame(minHeight: 44)
            Divider().overlay(Theme.line)
            HStack {
                SecureField("New password (8+ characters)", text: $newPassword)
                    .textContentType(.newPassword)
                Button("Change") {
                    Task { if await feed.changePassword(to: newPassword) { newPassword = "" } }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .disabled(newPassword.count < 8 || feed.isBusy)
            }
            .frame(minHeight: 44)
        }
        .softCardStyle()
    }
}

/// How the border around your picture is earned, and how close the next one is.
struct PathView: View {
    let progress: PathProgress
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NagisenHeader("Path", subtitle: "Borders you earn by showing up.", onBack: { dismiss() })
                VStack(spacing: 14) {
                    AvatarView(url: feed.avatarURL(feed.avatarPath), username: feed.username ?? "N",
                               tier: progress.tier, size: 112)
                    Text(progress.tier.name)
                        .font(.system(size: 25, design: .serif))
                    Text("\(progress.points) points")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    if let next = progress.tier.next, let needed = progress.pointsToNext {
                        ProgressView(value: progress.fractionToNext)
                            .tint(Theme.accent)
                        Text("\(needed) more to \(next.name)")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .softCardStyle()

                VStack(spacing: 0) {
                    row("Days checked", count: progress.checkedDays, each: PathProgress.pointsPerCheckedDay)
                    Divider().overlay(Theme.line)
                    row("Calorie goal hit", count: progress.goalDays, each: PathProgress.pointsPerGoalDay)
                    Divider().overlay(Theme.line)
                    row("7-day streaks", count: progress.weekStreaks, each: PathProgress.pointsPerWeekStreak)
                    Divider().overlay(Theme.line)
                    row("30-day streaks", count: progress.monthStreaks, each: PathProgress.pointsPerMonthStreak)
                    Divider().overlay(Theme.line)
                    row("Daily packs finished", count: progress.finishedPacks, each: PathProgress.pointsPerPack)
                    Divider().overlay(Theme.line)
                    row("Personal records beaten", count: progress.personalRecords, each: PathProgress.pointsPerRecord)
                    Divider().overlay(Theme.line)
                    row("Milestone trophies", count: progress.milestones, each: PathProgress.pointsPerMilestone)
                }
                .softCardStyle()

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(BorderTier.allCases.filter { $0 != .none }, id: \.self) { tier in
                        HStack(spacing: 14) {
                            Circle()
                                .strokeBorder(AngularGradient(colors: tier.colors, center: .center), lineWidth: 4)
                                .frame(width: 30, height: 30)
                                .opacity(progress.tier >= tier ? 1 : 0.35)
                            Text(tier.name).font(.body.weight(.medium))
                            Spacer()
                            Text(progress.tier >= tier ? "Earned" : "\(tier.threshold) points")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .softCardStyle()

                Text("Check off your day, land within 10% of your calorie goal, keep your streak going, finish a challenge pack, beat a lift or earn a workout trophy. Days imported from Lose It! don't count. Your border shows next to your posts and comments.")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ title: String, count: Int, each: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count) × \(each)").foregroundStyle(Theme.muted)
            Text("\(count * each)").font(.body.weight(.semibold)).frame(minWidth: 34, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}
