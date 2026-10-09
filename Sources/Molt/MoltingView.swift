import AppKit
import MoltCore
import SwiftUI

/// Molting: meet other Molt users, hang out in a shared playground, and lend your setup.
struct MoltingView: View {
  @ObservedObject var social: SocialController
  @ObservedObject var account: AccountController
  var appearance: Appearance
  @State private var username = ""
  @State private var side = "online"
  var body: some View {
    Group {
      if let hangout = social.hangout {
        HangoutView(social: social, hangout: hangout, myPalette: account.profile?.palette ?? appearance.palette)
      } else {
        HStack(alignment: .top, spacing: 12) {
          me.frame(width: 190)
          people
          sidebar.frame(width: 200)
        }
      }
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
    .onAppear { social.start(); social.refresh() }
  }

  private var me: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        CreatureView(appearance: palette(account.profile?.palette ?? appearance.palette), mood: "happy", moving: false)
          .frame(width: 34, height: 32)
        VStack(alignment: .leading, spacing: 1) {
          Text("@\(account.profile?.username ?? "you")").font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Text(account.profile?.socialTitle ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 6) {
        badge("star.fill", "\(account.profile?.points ?? 0)", "points", .yellow)
        badge("person.2.fill", "\(account.profile?.social ?? 0)", "hangouts", .pink)
      }
      Spacer(minLength: 0)
      HStack(spacing: 4) {
        TextField("Add @username", text: $username).textFieldStyle(.plain).font(.system(size: 11))
          .padding(.horizontal, 8).frame(height: 24)
          .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
          .onSubmit(add)
        Button(action: add) { Image(systemName: "person.badge.plus").font(.system(size: 11, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 24)).help("Send a friend request").accessibilityLabel("Send a friend request")
      }
      if !social.status.isEmpty {
        Text(social.status).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
      }
    }
    .padding(10).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
  }

  private var people: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(social.invites) { invite in
          row(invite.from, online: true) {
            Text("wants to hang out").font(.system(size: 10)).foregroundStyle(Color.accentColor)
          } actions: {
            iconButton("checkmark", "Join") { social.accept(invite) }
            iconButton("xmark", "Not now") { social.decline(invite) }
          }
        }
        ForEach(social.requests) { friend in
          row(friend.profile, online: social.onlineIDs.contains(friend.id)) {
            Text("wants to be friends").font(.system(size: 10)).foregroundStyle(.secondary)
          } actions: {
            iconButton("checkmark", "Accept") { social.accept(friend) }
            iconButton("xmark", "Decline") { social.remove(friend) }
          }
        }
        ForEach(social.friendsAccepted) { friend in
          let online = social.onlineIDs.contains(friend.id)
          row(friend.profile, online: online) {
            Text(online ? social.doing(friend.id) ?? "Online" : friend.profile.socialTitle).font(.system(size: 10))
              .foregroundStyle(online ? Color.green : .secondary).lineLimit(1)
          } actions: {
            iconButton("figure.2", "Hang out") { social.invite(friend.profile) }.disabled(!online)
            Menu {
              Button("Lend for a day") { social.lend(to: friend.profile, days: 1) }
              Button("Lend for a week") { social.lend(to: friend.profile, days: 7) }
              Button("Lend until returned") { social.lend(to: friend.profile, days: nil) }
              Divider()
              Button("Remove friend", role: .destructive) { social.remove(friend) }
            } label: {
              Image(systemName: "gift.fill").font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26, height: 26)
            .help("Lend your setup").accessibilityLabel("Lend your setup, or remove friend")
          }
        }
        ForEach(social.sent) { friend in
          row(friend.profile, online: false) {
            Text("Request sent").font(.system(size: 10)).foregroundStyle(.secondary)
          } actions: {
            iconButton("xmark", "Cancel request") { social.remove(friend) }
          }
        }
        if social.friends.isEmpty && social.invites.isEmpty {
          Text("No friends yet. Add someone by @username, or say hi to someone online.")
            .font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        chip("Online now", selected: side == "online") { side = "online" }
        chip("Loans", selected: side == "loans") { side = "loans" }
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          if side == "online" {
            if social.discover.isEmpty {
              Text("No one new is online right now.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 4)
            }
            ForEach(social.discover) { profile in
              HStack(spacing: 6) {
                CreatureView(appearance: palette(profile.palette), mood: "idle", moving: false).frame(width: 22, height: 20)
                Text("@\(profile.username)").font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                iconButton("person.badge.plus", "Add friend") { social.addFriend(profile) }
              }
            }
          } else {
            loans
          }
        }
      }
    }
    .padding(10).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
  }

  @ViewBuilder private var loans: some View {
    let me = social.me
    if let borrowing = social.borrowing {
      VStack(alignment: .leading, spacing: 4) {
        Text("Wearing \(borrowing.title)").font(.system(size: 11, weight: .medium)).lineLimit(1)
        Button("Give it back", action: social.giveBack)
      }
    }
    ForEach(social.loans.filter { $0.borrower == me && $0.id != social.borrowing?.id }) { loan in
      HStack {
        VStack(alignment: .leading, spacing: 0) {
          Text(loan.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
          Text(loan.expires.map { "until " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "until returned")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button("Try on") { social.borrow(loan) }.disabled(social.borrowing != nil)
      }
    }
    ForEach(social.loans.filter { $0.owner == me }) { loan in
      HStack {
        Text("Lent: \(friendName(loan.borrower))").font(.system(size: 11)).lineLimit(1)
        Spacer(minLength: 0)
        iconButton("arrow.uturn.backward", "Take back") { social.takeBack(loan) }
      }
    }
    if social.loans.isEmpty && social.borrowing == nil {
      Text("Lend your widgets and colors to a friend from the gift button.").font(.system(size: 10)).foregroundStyle(.secondary)
    }
  }

  private func row<Detail: View, Actions: View>(
    _ profile: Profile, online: Bool, @ViewBuilder detail: () -> Detail, @ViewBuilder actions: () -> Actions
  ) -> some View {
    HStack(spacing: 8) {
      ZStack(alignment: .bottomTrailing) {
        CreatureView(appearance: palette(profile.palette), mood: online ? "happy" : "idle", moving: false).frame(width: 30, height: 28)
        if online { Circle().fill(Color.green).frame(width: 7, height: 7).overlay(Circle().stroke(Color.black, lineWidth: 1.5)) }
      }
      VStack(alignment: .leading, spacing: 1) {
        Text("@\(profile.username)").font(.system(size: 12, weight: .medium)).lineLimit(1)
        detail()
      }
      Spacer(minLength: 4)
      actions()
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
  }
  private func badge(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon).font(.system(size: 9)).foregroundStyle(tint)
      Text(value).font(.system(size: 11, weight: .semibold).monospacedDigit())
    }
    .padding(.horizontal, 7).frame(height: 20)
    .background(Capsule().fill(Color.white.opacity(0.07)))
    .accessibilityElement().accessibilityLabel("\(value) \(label)")
  }
  private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
      .buttonStyle(NotchIconButtonStyle(size: 26)).help(label).accessibilityLabel(label)
  }
  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 10, weight: .semibold))
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
        .padding(.horizontal, 8).frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
        .contentShape(Capsule())
    }.buttonStyle(.plain)
  }
  private func palette(_ name: String) -> Appearance {
    var value = appearance
    value.palette = name
    return value
  }
  private func friendName(_ id: UUID) -> String {
    social.friends.first { $0.id == id }.map { "@" + $0.profile.username } ?? "a friend"
  }
  private func add() {
    social.addFriend(username)
    username = ""
  }
}

/// Two Molts in a shared playground. Click anywhere to walk there; emotes float above.
struct HangoutView: View {
  @ObservedObject var social: SocialController
  var hangout: SocialController.Hangout
  var myPalette: String
  @Environment(\.moltReducedMotion) private var reduced
  static let emotes: [(String, String, Color)] = [
    ("wave", "hand.wave.fill", .yellow), ("heart", "heart.fill", .pink), ("dance", "music.note", .cyan), ("laugh", "face.smiling.inverse", .orange),
  ]
  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        if let reward = hangout.reward {
          Image(systemName: reward > 0 ? "star.fill" : "star").foregroundStyle(.yellow)
          Text(reward > 0 ? "Great hangout! You both earned +\(reward) points." : "Hangout over. Stay a minute or more to earn points (once an hour per friend).")
            .font(.system(size: 12, weight: .medium))
          Spacer()
          Button("Done", action: social.dismissSummary)
        } else if social.waitingFor != nil {
          ProgressView().controlSize(.mini)
          Text("Waiting for @\(hangout.friend.username) to join…").font(.system(size: 12, weight: .medium))
          Spacer()
          Button("Cancel", action: social.cancelWaiting)
        } else {
          Image(systemName: "figure.2").foregroundStyle(Color.accentColor)
          Text("Hanging out with @\(hangout.friend.username)").font(.system(size: 12, weight: .semibold))
          if let started = hangout.started {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              Text(Self.clock(context.date.timeIntervalSince(started))).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
          }
          Spacer()
          ForEach(Self.emotes, id: \.0) { emote in
            Button { social.emote(emote.0) } label: { Image(systemName: emote.1).font(.system(size: 12)).foregroundStyle(emote.2) }
              .buttonStyle(NotchIconButtonStyle(size: 26)).help(emote.0.capitalized).accessibilityLabel(emote.0.capitalized)
          }
          Button("Leave", action: social.leave)
        }
      }
      GeometryReader { proxy in
        ZStack {
          RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
            LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.1), Color(red: 0.05, green: 0.08, blue: 0.07)], startPoint: .top, endPoint: .bottom))
          molt(palette: myPalette, at: hangout.me, emote: hangout.myEmote, name: "You", in: proxy.size)
          if let them = hangout.them {
            molt(palette: hangout.friend.palette, at: them, emote: hangout.theirEmote, name: "@" + hangout.friend.username, in: proxy.size)
          }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
          guard hangout.reward == nil else { return }
          social.move(to: CGPoint(x: value.location.x / proxy.size.width, y: value.location.y / proxy.size.height))
        })
        .accessibilityLabel("Playground. Click to walk there.")
      }
    }
  }
  private func molt(palette: String, at point: CGPoint, emote: String?, name: String, in size: CGSize) -> some View {
    var appearance = Appearance()
    appearance.palette = palette
    let x = 30 + point.x * max(0, size.width - 60)
    let y = 30 + point.y * max(0, size.height - 50)
    return VStack(spacing: 1) {
      if let emote, let symbol = Self.emotes.first(where: { $0.0 == emote }) {
        Image(systemName: symbol.1).font(.system(size: 13, weight: .semibold)).foregroundStyle(symbol.2)
          .transition(.scale.combined(with: .opacity))
      }
      CreatureView(appearance: appearance, mood: emote == nil ? "idle" : "happy", moving: !reduced).frame(width: 44, height: 41)
      Text(name).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
    }
    .position(x: x, y: y)
    .animation(reduced ? nil : .easeInOut(duration: 0.6), value: point)
    .animation(.spring(response: 0.3), value: emote)
  }
  static func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}
