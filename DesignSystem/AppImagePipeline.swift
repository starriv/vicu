import Foundation
import Nuke

enum AppImagePipeline {
    // Memory: 100 MB decoded image bytes. Disk: 200 MB DataCache, .automatic policy.
    static func makeShared() {
        ImagePipeline.shared = ImagePipeline {
            $0.dataCache = try? DataCache(name: "com.starriv.vicu.imagedata")
            $0.dataCachePolicy = .automatic
            $0.imageCache = ImageCache(
                costLimit: 100 * 1024 * 1024,
                countLimit: 200
            )
        }
    }
}

