import SwiftUI

@main
struct SwipeeApp: App {
    @StateObject private var settings = CandidateSettingsStore()
    @StateObject private var history = ReviewHistoryStore()
    @StateObject private var pendingDeletions = PendingDeletionStore()
    @StateObject private var reviewSession = ReviewSessionStore()
    @StateObject private var duplicateAnalysis = DuplicateAnalysisService()
    @StateObject private var duplicateSessions = DuplicateSessionStore()
    @StateObject private var duplicateReviewed = DuplicateReviewedStore()
    @StateObject private var photoLibrary = PhotoLibraryService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(pendingDeletions)
                .environmentObject(reviewSession)
                .environmentObject(duplicateAnalysis)
                .environmentObject(duplicateSessions)
                .environmentObject(duplicateReviewed)
                .environmentObject(photoLibrary)
        }
    }
}
