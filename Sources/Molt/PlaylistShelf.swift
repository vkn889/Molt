import AppKit
import SwiftUI

/// Your Spotify and Apple Music playlists as a row of covers. Clicking one plays it in the
/// background, without opening the music app.
struct PlaylistShelf: View {
  @ObservedObject var library: MusicLibrary
  var close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        ForEach([Playlist.Source.spotify, .appleMusic], id: \.self) { source in
          Button { library.source = source } label: {
            Text(source.rawValue).font(.system(size: 11, weight: .semibold))
              .foregroundStyle(library.source == source ? Color.white : Color.white.opacity(0.45))
              .padding(.horizontal, 9).frame(height: 22)
              .background(Capsule().fill(Color.white.opacity(library.source == source ? 0.14 : 0)))
              .contentShape(Capsule())
          }.buttonStyle(.plain)
        }
        Spacer()
        Button(action: library.refresh) { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 24)).help("Reload playlists").accessibilityLabel("Reload playlists")
        Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
          .buttonStyle(NotchIconButtonStyle(size: 24)).help("Back to your week").accessibilityLabel("Close playlists")
      }
      switch library.source {
      case .spotify: SpotifyShelf(account: library.spotify, library: library)
      case .appleMusic: AppleMusicShelf(music: library.appleMusic, library: library)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear(perform: library.refresh)
  }
}

private struct SpotifyShelf: View {
  @ObservedObject var account: SpotifyAccount
  let library: MusicLibrary
  var body: some View {
    if account.connected {
      Covers(
        playlists: account.playlists, loading: account.loading, status: account.status,
        image: { playlist in AnyView(RemoteCover(url: playlist.imageURL)) },
        play: library.play)
    } else {
      SpotifyConnect(account: account)
    }
  }
}

/// Spotify only lets registered apps sign in, so you create a free app once and paste its ID.
struct SpotifyConnect: View {
  @ObservedObject var account: SpotifyAccount
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        TextField("Spotify Client ID", text: $account.clientID)
          .textFieldStyle(.roundedBorder).font(.system(size: 11)).onSubmit(account.connect)
        Button(account.connecting ? "Waiting…" : "Connect", action: account.connect).disabled(account.connecting)
      }
      Text(account.status.isEmpty
        ? "Create an app at developer.spotify.com, add \(SpotifyAccount.redirect) as its redirect URI, then paste its Client ID."
        : account.status)
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
      Link("Open Spotify dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
        .font(.system(size: 10, weight: .medium))
    }
  }
}

private struct AppleMusicShelf: View {
  @ObservedObject var music: AppleMusicLibrary
  let library: MusicLibrary
  var body: some View {
    if music.connected {
      Covers(
        playlists: music.playlists, loading: music.loading, status: music.status,
        image: { playlist in
          AnyView(
            Group {
              if let image = music.covers[playlist.reference] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
              } else {
                CoverPlaceholder()
              }
            }.onAppear { music.loadCover(playlist) })
        },
        play: library.play)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Button("Connect Apple Music", action: music.connect).disabled(!music.installed)
        Text(music.installed
          ? "Shows the playlists in your library. Molt plays them with Music hidden in the background."
          : "Apple Music is not installed on this Mac.")
          .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct Covers: View {
  var playlists: [Playlist]
  var loading: Bool
  var status: String
  var image: (Playlist) -> AnyView
  var play: (Playlist) -> Void
  var body: some View {
    if playlists.isEmpty {
      HStack(spacing: 8) {
        if loading { ProgressView().controlSize(.small) }
        Text(loading ? "Loading playlists…" : status.isEmpty ? "No playlists yet." : status)
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 2) {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: 10) {
            ForEach(playlists) { playlist in
              Button { play(playlist) } label: {
                VStack(alignment: .leading, spacing: 3) {
                  image(playlist).frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                  Text(playlist.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.85)).frame(width: 58, alignment: .leading)
                }.contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .help("Play \(playlist.name) · \(playlist.detail)")
              .accessibilityLabel("Play \(playlist.name)")
            }
          }
        }
        if !status.isEmpty { Text(status).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1) }
      }
    }
  }
}

struct CoverPlaceholder: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: "music.note.list").font(.system(size: 16)).foregroundStyle(Color.white.opacity(0.35))
    }
  }
}

/// Loads a cover from Spotify's image CDN only.
struct RemoteCover: View {
  var url: URL?
  @State private var image: NSImage?
  var body: some View {
    Group {
      if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) } else { CoverPlaceholder() }
    }
    .task(id: url) {
      guard let url, url.scheme == "https", let host = url.host,
        host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com")
      else { return }
      if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
      guard let (data, _) = try? await URLSession.shared.data(from: url), data.count < 3_000_000,
        let loaded = NSImage(data: data)
      else { return }
      Self.cache.setObject(loaded, forKey: url as NSURL)
      image = loaded
    }
  }
  static let cache = NSCache<NSURL, NSImage>()
}
