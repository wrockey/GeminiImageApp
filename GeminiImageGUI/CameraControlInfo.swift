//
//  CameraControlInfo.swift
//  GeminiImageGUI
//
//  Created by William Rockey on 10/10/25.
//


import Foundation

struct CameraControlInfo {
    struct Info {
        let description: String
        let supportedControls: [String]
        let format: String
    }
    
    static func infoForModel(id: String) -> Info {
        let lowerID = id.lowercased()
        switch lowerID {
        case "klingai/v1-standard/text-to-video", "klingai/v1-pro/text-to-video", "klingai/v1-standard/image-to-video", "klingai/v1-pro/image-to-video", "klingai/v1.6-standard/image-to-video", "klingai/v1.6-pro/image-to-video", "klingai/v2.1-master-text-to-video", "klingai/v2.1-standard/image-to-video":
            return Info(
                description: "KlingAI models support up to 6-axis camera movements with precise control. Use numeric values (-10 to 10) for intensity or direction strings. Select up to 4 controls for Pro models, 6 for Standard/Master.",
                supportedControls: ["Pan (left/right, -10 to 10)", "Tilt (up/down, -10 to 10)", "Zoom (in/out, -10 to 10)", "Roll (left/right, -10 to 10)", "Dolly (forward/back)", "Track (left/right)"],
                format: "JSON object, e.g., {\"pan\": \"left\", \"tilt\": 5, \"zoom\": \"in\", \"roll\": -4}"
            )
        case "openai/sora-2-text-to-video", "openai/sora-2-i2v":
            return Info(
                description: "Sora 2 supports cinematic camera movements, often integrated with the prompt. Use JSON for explicit control or describe movements in the prompt for flexibility.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)", "Roll (left/right)", "Dolly (forward/back)", "Track (left/right)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"in\"}, or prompt-based, e.g., \"pan left, zoom in on face\""
            )
        case "google/veo2/image-to-video", "google/veo-3.0-i2v":
            return Info(
                description: "Google Veo models support dynamic camera movements for precise shots. Use JSON for structured control or include movements in the prompt for natural effects.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)", "Dolly (forward/back)", "Track (left/right)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"out\"}, or prompt-based, e.g., \"dolly forward, tilt up\""
            )
        case "minimax/video-01", "minimax/hailuo-02":
            return Info(
                description: "MiniMax models support up to 15 camera movements, with a limit of 3 per generation. Use action verbs in JSON or prompt for natural motion, especially enhanced in Hailuo-02.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)", "Fly Over (forward)", "Truck (left/right)", "Dolly (forward/back)"],
                format: "JSON, e.g., {\"zoom\": \"in\", \"pan\": \"left\"}, or prompt-based, e.g., \"zoom in, truck left\""
            )
        case "pixverse/v5/image-to-video":
            return Info(
                description: "PixVerse supports basic camera movements with a focus on stylistic video output. Use JSON for control or describe in prompt.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"in\"}"
            )
        case "runway/gen3a_turbo":
            return Info(
                description: "Runway Gen3a Turbo supports basic camera movements for smooth video transitions. Use JSON for structured input.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"out\"}"
            )
        case "alibaba/wan-2.1-plus", "alibaba/wan-2.1-turbo", "alibaba/wan-2.2-plus", "alibaba/wan-2.5-preview", "alibaba/wan-2.5-preview-i2v":
            return Info(
                description: "Alibaba Wan models support basic camera movements. Limited documentation; assume standard controls.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"in\"}"
            )
        case "bytedance/seedance-1-0-lite-t2v", "bytedance/seedance-1-0-lite-i2v", "bytedance/seedance-1-0-pro-t2v", "bytedance/seedance-1-0-pro-i2v", "bytedance/omnihuman":
            return Info(
                description: "ByteDance Seedance models support basic camera movements. Use JSON for control; limited to simpler motions.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"in\"}"
            )
        default:
            return Info(
                description: "Generic video model with standard camera controls. Use JSON for structured input or describe in prompt.",
                supportedControls: ["Pan (left/right)", "Tilt (up/down)", "Zoom (in/out)", "Dolly (forward/back)", "Track (left/right)"],
                format: "JSON, e.g., {\"pan\": \"left\", \"zoom\": \"in\"}"
            )
        }
    }
}