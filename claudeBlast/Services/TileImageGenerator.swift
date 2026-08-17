// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageGenerator.swift
//  claudeBlast
//
//  Generate a first-pass tile image for a word via the OpenAI images API, styled
//  to match the ACTIVE image set so a generated tile sits alongside the bundled
//  ones (Playful 3D clay, High Contrast, or the flat ARASAAC-style pictogram).
//  The style strings are ported from tools/generate_sets.py so in-app generation
//  matches the offline tile-set workflow. The result is just another source of
//  TileModel.userImageData — callers run it through TilePhotoProcessor and store
//  it like a photo, so it renders everywhere via TileImageResolver and syncs.
//

import Foundation
import UIKit

enum TileImageGenerator {
    /// OpenAI images model. `gpt-image-1` is the current model (dall-e-3 is
    /// retired on the images endpoint). It always returns base64 and does NOT
    /// accept `response_format`; `quality` is low/medium/high/auto (not dall-e-3's
    /// standard/hd). Swap here to change the model later.
    private static let model = "gpt-image-1"
    private static let quality = "medium" // low | medium | high | auto

    /// Generate a square (1024²) image for a word, styled to `imageSet`. Caller
    /// downscales/compresses via TilePhotoProcessor before storing. Throws
    /// OpenAIError on failure.
    /// Soft cap on the optional refinement detail (e.g. "purple tail and mane").
    static let maxDetailLength = 120
    /// Show the character counter only within the last 20% of the cap.
    static var detailCounterThreshold: Int { maxDetailLength * 4 / 5 }

    /// Generate a word's art in each of `styles`, keyed by the set it belongs to.
    ///
    /// ## One base image, N transforms — per style
    ///
    /// **A style is the unit art is generated in.** Each style generates its base
    /// ONCE and then transforms it once per remaining variant, each transform
    /// starting from the previous one's output. That is exactly how the shipped
    /// sets were built (`build_tone_variants.py --chain`), so a word added on
    /// device and a word in the bundle arrive by the same process.
    ///
    /// Generating per *set* instead produced a different picture for each: adding
    /// "swimmer" gave three different swimmers across Light, Medium and Dark —
    /// different poses, different swimsuits, one in a cap. In AAC the figure is
    /// the referent, so a child whose caregiver switches tone would have met a
    /// different person.
    ///
    /// A style with one variant needs no special case; it is the loop with zero
    /// transforms. If Playful 3D ever gains tones, it works here unchanged.
    ///
    /// How many styles and how far into each is `ArtPlan`'s decision, not this
    /// function's — see the note there on why that is one place and not three.
    ///
    /// Returns art per set. A style whose base fails contributes nothing and the
    /// others still land; a transform that fails ends that style's chain there,
    /// since every variant below it would have been derived from the missing one.
    static func generate(displayName: String,
                         wordClass: String,
                         plan: [PlannedStyle],
                         detail: String = "",
                         apiKey: String) async -> [ImageSetID: UIImage] {
        guard !apiKey.isEmpty else { return [:] }
        var out: [ImageSetID: UIImage] = [:]

        for planned in plan {
            guard var image = try? await generateBase(displayName: displayName,
                                                      wordClass: wordClass,
                                                      imageSet: planned.base.id,
                                                      detail: detail,
                                                      apiKey: apiKey) else { continue }
            out[planned.base.id] = image

            guard planned.needsSkinCheck else { continue }
            let wanted = planned.transforms

            // A picture with no person in it is the same picture in every
            // variant — a white house is a white house at any skin tone. Copy it
            // across rather than transforming, which would invent a person.
            guard await depictsSkin(image, apiKey: apiKey) else {
                for variant in wanted { out[variant.id] = image }
                continue
            }

            var from = planned.base.id
            for variant in wanted {
                // Absent rather than falling back to the untransformed image: a
                // set silently populated with the wrong skin tone is the exact
                // failure these sets exist to prevent, and the caller reports
                // what is missing by name.
                guard let next = try? await transform(image, from: from, to: variant.id,
                                                      apiKey: apiKey) else { break }
                out[variant.id] = next
                image = next
                from = variant.id
            }
        }
        return out
    }

    /// Fill in a style's missing variants for one word, from the art it already
    /// has. No new picture is drawn — this is transforms only.
    ///
    /// This is the other half of stopping at the active variant. A caregiver on
    /// Medium adds twenty-five words and gets Light and Medium art for each; if
    /// she later wants the whole style complete, each word needs Dark and nothing
    /// more. Asking her to predict that up front — a "generate every variant"
    /// setting — makes her pay for Dark before she has ever wanted it, for the
    /// same money. This asks at the moment she actually wants it.
    ///
    /// `existing` is the art the word already has, per set. The walk carries the
    /// last image it has seen, so a gap is transformed from whatever sits above
    /// it, and a word with only base art fills the whole chain. A word with no
    /// base art at all yields nothing: there is nothing to transform, and drawing
    /// a fresh one would be a different picture from the rest of its style.
    ///
    /// Returns only the newly produced art.
    static func fillMissingVariants(style: TileStyle,
                                    existing: [ImageSetID: UIImage],
                                    apiKey: String) async -> [ImageSetID: UIImage] {
        guard !apiKey.isEmpty else { return [:] }
        guard style.variants.contains(where: { existing[$0.id] == nil }),
              let first = style.variants.compactMap({ existing[$0.id] }).first
        else { return [:] }

        // Same rule as generation: a picture with no person is identical in
        // every variant, so it is copied, never transformed.
        guard await depictsSkin(first, apiKey: apiKey) else {
            var copies: [ImageSetID: UIImage] = [:]
            for variant in style.variants where existing[variant.id] == nil {
                copies[variant.id] = first
            }
            return copies
        }

        var produced: [ImageSetID: UIImage] = [:]
        var carry: UIImage?
        var from: ImageSetID?

        for variant in style.variants {
            if let have = existing[variant.id] {
                carry = have
                from = variant.id
                continue
            }
            guard let source = carry, let previous = from,
                  let filled = try? await transform(source, from: previous,
                                                    to: variant.id, apiKey: apiKey)
            else { break }   // the chain cannot skip a link
            produced[variant.id] = filled
            carry = filled
            from = variant.id
        }
        return produced
    }

    /// A style's base art — the raw generation everything else transforms from.
    private static func generateBase(displayName: String,
                                     wordClass: String,
                                     imageSet: ImageSetID,
                                     detail: String,
                                     apiKey: String) async throws -> UIImage {
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt(displayName: displayName, wordClass: wordClass,
                             imageSet: imageSet, detail: detail),
            "size": "1024x1024",
            "quality": quality,
            "n": 1,
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        return try await UsageContext.$current.withValue(
            UsageContext(cause: .tileImageGenerate, detail: imageSet.rawValue)
        ) {
            try await send(request, cause: .tileImageGenerate,
                           endpoint: OpenAIEndpoint.imagesGenerations)
        }
    }

    /// Does this picture contain a person — anything with skin to recolour?
    ///
    /// **A tone transform applied to a picture with no person destroys it.** The
    /// prompt asserts "the figure currently has light skin", and the model obeys
    /// an instruction about a figure by inventing one: adding "White House" gave
    /// a building in Light and a *child eating dinner* in Medium and Dark, and
    /// "speed boat" became a boy eating a sandwich. The prompt cannot be softened
    /// into "recolour any skin you find" — it earns its accuracy by being
    /// specific, and hedging it costs tone precision on the tiles that do have
    /// people.
    ///
    /// So the picture is looked at first. Ported from
    /// `build_tone_variants.py --classify`, which asked exactly this before
    /// refining any of the 552 shipped tiles and copied the rest byte-for-byte.
    /// The offline build needed it for the same reason and I failed to port it.
    ///
    /// ~$0.0004 per call against ~$0.044 per transform it may save, so it pays
    /// for itself on any word without a person in it.
    ///
    /// **Returns false when the check itself fails.** Copying is the safer
    /// wrong answer: an untransformed person is a familiar figure in the wrong
    /// skin tone, while a transformed object is a different picture altogether.
    private static func depictsSkin(_ image: UIImage, apiKey: String) async -> Bool {
        guard let png = image.pngData() else { return false }
        let body: [String: Any] = [
            "model": ModelID.authoring,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": classifyPrompt],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/png;base64,\(png.base64EncodedString())",
                                   "detail": "low"]],
                ],
            ]],
            "max_tokens": 3,
            "temperature": 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 30

        let answer: String? = try? await UsageContext.$current.withValue(
            UsageContext(cause: .tileArtClassify, detail: "")
        ) {
            let (payload, response) = try await OpenAIClient.send(
                request, cause: .tileArtClassify, endpoint: OpenAIEndpoint.chatCompletions)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { throw OpenAIError.decodingError("No answer from the art check") }
            return text
        }
        guard let answer else { return false }
        return answer.lowercased().contains("yes")
    }

    private static let classifyPrompt = """
        This is a pictogram from an AAC (augmentative communication) symbol set. \
        Answer with one word, yes or no: does it depict a human being or any \
        human body part with visible skin — a face, hand, arm, or whole figure? \
        Answer no for animals, objects, food, places, and abstract symbols with \
        no person in them.
        """

    /// Apply one variant transform, `from` → `to`, within a style.
    ///
    /// Skin tone is the only transform that exists today, so this is a recolour.
    /// A style whose variants differ some other way would branch here on what
    /// `to` declares — the shape of the call, one image in and one image out, is
    /// what the generation loop depends on and would not change.
    ///
    /// A caregiver on "Classic — Dark" who adds *policeman* gets art drawn in
    /// Classic's style, and Classic is light-skinned — so without this the new
    /// word arrives as the only light-skinned figure in their set. That is exactly
    /// the absence these sets exist to remove.
    ///
    /// ## Why one image and an explicit target, not an exemplar
    ///
    /// The first version passed **two** images to /images/edits — the new art plus
    /// an existing correctly-toned tile as a colour swatch — on the reasoning that
    /// a tone cannot be described in words. That shipped and was wrong on both
    /// counts. Multi-image input to gpt-image-1 is *reference composition*, not an
    /// edit of the first image: adding "swimmer" with all styles on came back as
    /// three different swimmers again, and the tone overshot well past the target.
    /// Repeated `image[]` says "here are references, make a picture", which is a
    /// different operation from "modify this picture".
    ///
    /// A single image plus the target as **channel values** is what
    /// `build_tone_variants.py` used to build the 552-tile shipped sets, so it is
    /// the recipe with 500+ reviewed results behind it. The prompt below is ported
    /// from its `chain_prompt`, including the two failure modes review actually
    /// caught: terracotta skin when blue is left unpinned, and blond hair left on
    /// brown skin.
    private static func transform(_ image: UIImage,
                                  from: ImageSetID,
                                  to: ImageSetID,
                                  apiKey: String) async throws -> UIImage {
        guard let target = to.toneTarget else { return image }
        guard let png = image.pngData() else {
            throw OpenAIError.decodingError("Couldn't encode the generated image")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        appendField("prompt", toneStepPrompt(from: from, to: target))
        appendField("size", "1024x1024")
        appendField("quality", quality)
        appendField("n", "1")
        // Single `image`, not repeated `image[]` — see the note above.
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n"
            .data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(png)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 90

        return try await UsageContext.$current.withValue(
            UsageContext(cause: .tileImageRefine, detail: to.rawValue)
        ) {
            try await send(request, cause: .tileImageRefine,
                           endpoint: OpenAIEndpoint.imagesEdits)
        }
    }

    /// Ported from `build_tone_variants.py:chain_prompt`. Keep the two in step —
    /// the shipped art and a runtime word-add have to land on the same palette,
    /// and they only do so because they ask for the same thing in the same terms.
    private static func toneStepPrompt(from: ImageSetID, to target: ToneTarget) -> String {
        let origin = from.toneTarget?.origin ?? "light skin (#F0B482)"
        return """
        The figure currently has \(origin). Darken the skin ONE STEP to \
        \(target.hex) — RGB red \(target.red), green \(target.green), blue \
        \(target.blue) — a \(target.summary) tone (\(target.label), \
        \(target.fitzpatrick), the \(target.emoji) emoji modifier).

        This is a small, controlled step along a skin-tone scale, not a jump. The \
        result must be clearly darker than \(origin). Land on \(target.hex): blue \
        should be about \(target.bluePercent)% of red and green about \
        \(target.greenPercent)% of red. A tone with too little blue reads as \
        orange, rust or terracotta, which is wrong. Keep it soft and slightly \
        desaturated — a natural skin tone, not a saturated colour. Do not go \
        darker than \(target.hex); err lighter if anything.

        HAIR: if the hair is blond, yellow, golden, light brown, or any pale \
        colour, you MUST change it to dark brown. Pale hair on brown skin is wrong \
        and is the most common mistake made on this task. Hair that is already \
        dark stays exactly as it is. Keep strong value contrast at the hairline so \
        it reads clearly against the skin, and never tint hair with the skin colour.

        Change NOTHING else. Same person, same pose, same facial expression, same \
        hairstyle, same clothing and identical clothing colours, same objects, \
        same background, same black outlines at the same weight, same composition. \
        Do not redraw or restyle. Do not recolour clothing, food, bread, wood, \
        sand, or any object — only skin. No text anywhere.
        """
    }

    /// Refine an existing image (image-to-image) via /images/edits: sends the
    /// current image + an instruction so the result keeps the base and applies
    /// just the change — true iterative refinement (each refine builds on the
    /// last image), unlike a fresh text-to-image generation.
    static func edit(baseImage: UIImage, instruction: String, apiKey: String) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }
        guard let png = baseImage.pngData() else {
            throw OpenAIError.decodingError("Couldn't encode the base image")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", model)
        appendField("prompt", editPrompt(instruction: instruction))
        appendField("size", "1024x1024")
        appendField("quality", quality)
        appendField("n", "1")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(png)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: "https://api.openai.com/v1/images/edits")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 90
        return try await send(request, cause: .tileImageRefine,
                              endpoint: OpenAIEndpoint.imagesEdits)
    }

    private static func editPrompt(instruction: String) -> String {
        let inst = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let change = inst.isEmpty ? "Refine the image" : inst
        return "\(change). Keep the same subject, composition, and art style."
    }

    /// Shared: run an images request, surface OpenAI's structured error, decode
    /// the returned image (base64 or URL).
    private static func send(_ request: URLRequest,
                             cause: UsageCause,
                             endpoint: String) async throws -> UIImage {
        let (data, response) = try await OpenAIClient.send(
            request, cause: cause, endpoint: endpoint)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: 0, body: "Invalid response")
        }
        guard http.statusCode == 200 else {
            // Surface OpenAI's structured error message (content policy, model
            // access, invalid parameter) rather than the raw body.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(statusCode: http.statusCode,
                                        body: String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try await decodeImage(data: data)
    }

    /// Build the prompt as `<style> Subject: <word> (<class>).` — mirroring
    /// tools/generate_sets.py `build_prompt`. The word class is a sense hint so
    /// ambiguous words resolve correctly (e.g. "snack bar (food)" → a granola bar,
    /// "snack bar (place)" → a building).
    private static func prompt(displayName: String, wordClass: String, imageSet: ImageSetID, detail: String) -> String {
        let base = "\(style(for: imageSet)) Subject: \(displayName) (\(wordClass))."
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : "\(base) \(trimmed)."
    }

    /// Style prefix per image set. Loaded from the shared `image_styles.json`
    /// (the single source of truth, also read by tools/generate_sets.py) so
    /// in-app generation matches the offline tile-set art. Falls back to a short
    /// built-in style only if the bundled file is missing/corrupt.
    private static func style(for imageSet: ImageSetID) -> String {
        // ImageSetID raw values are the JSON keys in image_styles.json (classic
        // carries its own entry — a flat ARASAAC-style pictogram recipe).
        // Look up by the set's declared style key rather than its id: the Classic
        // tone variants have their own ids but are drawn in Classic's style, and
        // `image_styles.json` has no entry under `classic_medium`. Without this
        // every tone-variant word-add would silently take the generic fallback.
        loadedStyles[ImageSetCatalog.descriptor(for: imageSet)?.stylePromptKey ?? imageSet.rawValue]
            ?? fallbackStyle(for: imageSet)
    }

    /// Decoded `image_styles.json` (key → style prefix), loaded once.
    private static let loadedStyles: [String: String] = {
        guard let url = Bundle.main.url(forResource: "image_styles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }()

    /// Minimal graceful-degradation styles if the JSON is unavailable. The
    /// authoritative long versions live in image_styles.json — keep these short.
    /// Keyed on the descriptor's `stylePromptKey`, not the set id, so the three
    /// Classic tone variants share Classic's style — they differ in skin tone,
    /// not in how the art is drawn — and an installed set falls back to its own
    /// declared style rather than to whichever case happened to be listed last.
    private static func fallbackStyle(for imageSet: ImageSetID) -> String {
        let styleKey = ImageSetCatalog.descriptor(for: imageSet)?.stylePromptKey ?? ""
        switch styleKey {
        case "playful_3d":
            return "3D clay/plasticine sculpture, soft rounded shapes, pastel-bright colors, clean solid-color background, no text. Square format, single clear subject centered."
        case "high_contrast", "high_contrast_v2":
            return "High-contrast pictogram: one bold white subject on a pure solid black background, thick clean lines, no frame, no border, no text. Square format, subject centered."
        default:
            return "Flat 2D AAC pictogram, bold clean outlines, bright saturated solid colors, white background, no text. Square format, single clear subject centered."
        }
    }

    private static func decodeImage(data: Data) async throws -> UIImage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.decodingError("Response was not JSON")
        }
        // Surface a structured API error if present (content policy, access, etc.)
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw OpenAIError.apiError(message)
        }
        guard let first = (json["data"] as? [[String: Any]])?.first else {
            throw OpenAIError.decodingError("No image in response")
        }
        // Inline base64 (current default)…
        if let b64 = first["b64_json"] as? String,
           let imgData = Data(base64Encoded: b64),
           let image = UIImage(data: imgData) {
            return image
        }
        // …or a URL to fetch.
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            let (imgData, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: imgData) { return image }
        }
        throw OpenAIError.decodingError("No image in response")
    }
}
