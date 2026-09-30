import AppKit
import CoreImage.CIFilterBuiltins
import MoltCore
import SwiftUI

/// Shown until this Mac has a Molt account. You only do this once.
struct AccountGate: View {
  @ObservedObject var account: AccountController
  var appearance: Appearance
  @State private var creating = true
  @State private var email = ""
  @State private var password = ""
  @State private var username = ""
  @State private var code = ""
  var body: some View {
    HStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        CreatureView(appearance: appearance, mood: "happy", moving: true).frame(width: 70, height: 65)
        Text("Welcome to Molt").font(.system(size: 17, weight: .semibold))
        Text("Create your account once. You stay signed in on this Mac.")
          .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.frame(width: 200, alignment: .leading)
      VStack(alignment: .leading, spacing: 7) {
        switch account.phase {
        case .loading:
          ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirmEmail(let address):
          Text("Check your email").font(.system(size: 14, weight: .semibold))
          Text("We sent a confirmation link to \(address). Click it, then come back and continue.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          HStack {
            Button("Continue", action: account.continueAfterConfirming).disabled(account.busy)
            Button("Use a different email") { account.signOut() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
          }
        case .needsCode:
          Text("Two-factor code").font(.system(size: 14, weight: .semibold))
          Text("Enter the 6-digit code from your authenticator app.").font(.system(size: 11)).foregroundStyle(.secondary)
          HStack {
            field("123456", text: $code).frame(width: 120).onSubmit { account.verifySignInCode(code) }
            Button("Verify") { account.verifySignInCode(code) }.disabled(account.busy)
            Button("Cancel") { account.signOut() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
          }
        default:
          HStack(spacing: 4) {
            chip("Create account", selected: creating) { creating = true }
            chip("Sign in", selected: !creating) { creating = false }
          }
          HStack(spacing: 6) {
            field("Email", text: $email)
            if creating {
              field("@username", text: $username).frame(width: 130)
            }
          }
          HStack(spacing: 6) {
            SecureField(creating ? "Password (8+ characters, a number)" : "Password", text: $password)
              .textFieldStyle(.plain).font(.system(size: 12)).padding(.horizontal, 10).frame(height: 28)
              .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
              .onSubmit(submit)
            Button(creating ? "Create" : "Sign in", action: submit).disabled(account.busy)
          }
          HStack {
            if account.busy { ProgressView().controlSize(.mini) }
            Text(account.status).font(.system(size: 10)).foregroundStyle(account.status.isEmpty ? .secondary : Color.orange).lineLimit(2)
            Spacer()
            if !creating {
              Button("Forgot password?") { account.resetPassword(email: email) }.buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 14)
  }
  private func submit() {
    if creating {
      account.signUp(email: email, password: password, username: username)
    } else {
      account.signIn(email: email, password: password)
    }
  }
  private func field(_ title: String, text: Binding<String>) -> some View {
    TextField(title, text: text).textFieldStyle(.plain).font(.system(size: 12))
      .padding(.horizontal, 10).frame(height: 28)
      .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
  }
  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 11, weight: .semibold))
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
        .padding(.horizontal, 10).frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
        .contentShape(Capsule())
    }.buttonStyle(.plain)
  }
}

/// Your account: username, points, discoverability, two-factor authentication and sign out.
struct AccountPanel: View {
  @ObservedObject var account: AccountController
  var close: () -> Void
  @State private var code = ""
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        if let profile = account.profile {
          Text("@\(profile.username)").font(.system(size: 15, weight: .semibold))
          Text("\(profile.points) points · \(profile.socialTitle)").font(.system(size: 11)).foregroundStyle(.secondary)
          HStack {
            Text("Show me in Online now").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8))
            Spacer()
            Toggle("Show me in Online now", isOn: Binding(get: { profile.discoverable }, set: { account.updateProfile(discoverable: $0) }))
              .labelsHidden().toggleStyle(.switch).controlSize(.mini)
          }
        }
        Spacer(minLength: 0)
        HStack {
          Button("Sign out", action: account.signOut)
          Spacer()
          Button("Done", action: close)
        }
      }
      .padding(12).frame(width: 250).frame(maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label("Two-factor authentication", systemImage: account.mfaEnabled ? "lock.shield.fill" : "lock.shield")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(account.mfaEnabled ? Color.green : Color.white)
          Spacer()
          if account.busy { ProgressView().controlSize(.mini) }
        }
        if let enrollment = account.enrollment {
          HStack(alignment: .top, spacing: 12) {
            QRCode(text: enrollment.uri).frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 5) {
              Text("Scan with an authenticator app, then enter its code.").font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              Text(enrollment.secret).font(.system(size: 9, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                .foregroundStyle(Color.white.opacity(0.6))
              HStack {
                TextField("123456", text: $code).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                  .padding(.horizontal, 8).frame(width: 90, height: 26)
                  .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                  .onSubmit { account.confirmTwoFactor(code) }
                Button("Turn on") { account.confirmTwoFactor(code) }
                Button("Cancel", action: account.cancelTwoFactor).buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
              }
            }
          }
        } else if account.mfaEnabled {
          Text("On. Signing in on a new Mac asks for a code from your authenticator app.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Button("Turn off", action: account.disableTwoFactor)
        } else {
          Text("Add a code from an authenticator app when you sign in. Molt reminds you weekly until it's on.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Button("Set up", action: account.startTwoFactor)
        }
        if !account.status.isEmpty {
          Text(account.status).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
        }
      }
      .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(NotchSurface(radius: 14))
    }
    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
  }
}

/// A QR code drawn locally with Core Image; the secret never leaves the Mac.
struct QRCode: View {
  var text: String
  var body: some View {
    if let image = Self.image(text) {
      Image(nsImage: image).interpolation(.none).resizable()
        .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .accessibilityLabel("QR code for your authenticator app")
    }
  }
  static func image(_ text: String) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
    let rep = NSCIImageRep(ciImage: output)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
  }
}
