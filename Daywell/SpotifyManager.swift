import Foundation
import Security
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyManager: NSObject, ObservableObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    @Published var trackName: String?
    @Published var artistName: String?
    @Published var artwork: UIImage?
    @Published var isConnected = false
    @Published var status = "Looking for your Spotify playback…"

    // Public Spotify app identifier; the Client Secret is never included in the iOS app.
    static let clientID = "abb075eecece4014ba7bcc4f6dfa5265"
    static let redirectURL = URL(string: "daywell-spotify-login://callback")!
    var isConfigured: Bool { !Self.clientID.isEmpty }

    private var appRemote: SPTAppRemote?
    private var lastTrackURI: String?
    private var isConnecting = false
    private var connectionAttempt = 0
    private let keychainAccount = "daywell.spotify.appremote.access-token"
    var hasSavedAuthorization: Bool { loadToken() != nil }

    override init() {
        super.init()
        guard isConfigured else { return }
        let configuration = SPTConfiguration(clientID: Self.clientID, redirectURL: Self.redirectURL)
        configuration.playURI = ""
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        appRemote = remote
        if loadToken() == nil { status = "Connect Spotify once to show your current song." }
    }

    func connect() {
        guard let remote = appRemote else {
            status = "Spotify setup is not finished yet."
            return
        }
        guard !remote.isConnected else { refreshCurrentTrack(); return }
        guard !isConnecting else { return }
        status = "Connecting to Spotify…"
        if let token = loadToken() {
            startConnection(remote, token: token)
        } else {
            authorize(remote)
        }
    }

    /// Manual recovery when a saved App Remote token no longer works.
    func authorizeAgain() {
        guard let remote = appRemote else { return }
        clearToken()
        remote.connectionParameters.accessToken = nil
        isConnecting = false
        authorize(remote)
    }

    private func authorize(_ remote: SPTAppRemote) {
        status = "Opening Spotify to connect…"
        remote.authorizeAndPlayURI("") { [weak self] installed in
            if !installed {
                DispatchQueue.main.async { self?.status = "Install Spotify on this iPhone to connect." }
            }
        }
    }

    private func startConnection(_ remote: SPTAppRemote, token: String) {
        guard !isConnecting, !remote.isConnected else { return }
        isConnecting = true
        connectionAttempt += 1
        let attempt = connectionAttempt
        remote.connectionParameters.accessToken = token
        remote.connect()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, self.connectionAttempt == attempt, !self.isConnected else { return }
            self.isConnecting = false
        }
    }

    func handle(url: URL) {
        guard url.scheme == Self.redirectURL.scheme,
              url.host == Self.redirectURL.host,
              let remote = appRemote else { return }
        let parameters = remote.authorizationParameters(from: url)
        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            saveToken(token)
            isConnecting = false
            startConnection(remote, token: token)
        } else {
            status = parameters?[SPTAppRemoteErrorDescriptionKey] ?? "Spotify authorization was cancelled."
        }
    }

    func connectIfAuthorized() {
        guard let remote = appRemote else { return }
        if remote.isConnected { refreshCurrentTrack(); return }
        guard let token = loadToken() else { return }
        status = "Looking for your Spotify playback…"
        startConnection(remote, token: token)
    }

    func disconnect() {
        if appRemote?.isConnected == true { appRemote?.disconnect() }
    }

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in self?.didConnect(appRemote) }
    }

    private func didConnect(_ appRemote: SPTAppRemote) {
        isConnecting = false
        isConnected = true
        status = "Connected to Spotify"
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.status = error.localizedDescription } }
        })
        refreshCurrentTrack()
    }

    func refreshCurrentTrack() {
        guard let remote = appRemote, remote.isConnected else { return }
        remote.playerAPI?.getPlayerState { [weak self] state, error in
            if let state = state as? SPTAppRemotePlayerState {
                self?.playerStateDidChange(state)
            } else if let error {
                DispatchQueue.main.async { self?.status = error.localizedDescription }
            }
        }
    }

    func previousTrack() {
        guard let remote = appRemote, remote.isConnected else { return }
        remote.playerAPI?.skip(toPrevious: nil)
    }

    func nextTrack() {
        guard let remote = appRemote, remote.isConnected else { return }
        remote.playerAPI?.skip(toNext: nil)
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor [weak self] in self?.didDisconnect(error: error) }
    }

    private func didDisconnect(error: Error?) {
        isConnecting = false
        isConnected = false
        status = error == nil ? "Reconnecting when you return…" : "Spotify disconnected. Open Spotify and return."
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor [weak self] in self?.didFailConnection() }
    }

    private func didFailConnection() {
        isConnecting = false
        isConnected = false
        trackName = nil
        artistName = nil
        artwork = nil
        lastTrackURI = nil
        status = "Open Spotify and return to see your current song."
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor [weak self] in
            self?.updatePlayerState(playerState)
        }
    }

    private func updatePlayerState(_ playerState: SPTAppRemotePlayerState) {
        trackName = playerState.track.name
        artistName = playerState.track.artist.name
        status = playerState.isPaused ? "Paused in Spotify" : "Playing in Spotify"
        guard lastTrackURI != playerState.track.uri else { return }
        lastTrackURI = playerState.track.uri
        artwork = nil
        appRemote?.imageAPI?.fetchImage(forItem: playerState.track,
                                        with: CGSize(width: 300, height: 300)) { [weak self] image, _ in
            DispatchQueue.main.async { self?.artwork = image as? UIImage }
        }
    }

    private func saveToken(_ token: String) {
        clearToken()
        guard let data = token.data(using: .utf8) else { return }
        SecItemAdd([kSecClass: kSecClassGenericPassword,
                    kSecAttrAccount: keychainAccount,
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                    kSecValueData: data] as CFDictionary, nil)
    }

    private func loadToken() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword,
                                          kSecAttrAccount: keychainAccount,
                                          kSecReturnData: true,
                                          kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func clearToken() {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrAccount: keychainAccount] as CFDictionary)
    }
}
