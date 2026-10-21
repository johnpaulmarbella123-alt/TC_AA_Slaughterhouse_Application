import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class DocumentVerificationResult {
  final bool isValid;
  final String message;
  final List<String> detectedKeywords;
  final String extractedSnippet;

  DocumentVerificationResult({
    required this.isValid,
    required this.message,
    this.detectedKeywords = const [],
    this.extractedSnippet = '',
  });
}

class DocumentVerifier {
  /// Verifies whether an image is a legitimate certificate or scanned document
  /// matching the specified [documentType].
  static Future<DocumentVerificationResult> verifyCertificate({
    required File imageFile,
    required String documentType,
  }) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await textRecognizer
          .processImage(inputImage)
          .timeout(const Duration(seconds: 4));

      final String fullText = recognizedText.text.toUpperCase();
      final List<String> words = fullText
          .split(RegExp(r'\s+'))
          .where((w) => w.trim().length > 1)
          .toList();

      debugPrint("OCR Document Verification - Total words detected: ${words.length}");

      // Reject images with almost no text (e.g. photos of objects, people, pets, landscapes)
      if (words.length < 5) {
        return DocumentVerificationResult(
          isValid: false,
          message:
              "The uploaded image does not appear to contain document text. Please upload a clear scanned certificate or take a photo of the physical document.",
          extractedSnippet: fullText.trim(),
        );
      }

      // 1. General Certificate & Authority Indicators
      final List<String> certKeywords = [
        "CERTIFICATE",
        "CERTIFY",
        "CERTIFICATION",
        "CERTIFIED",
        "CLEARANCE",
        "PERMIT",
        "TO WHOM IT MAY CONCERN",
        "LICENSING",
        "REGISTRATION",
      ];

      final List<String> authorityKeywords = [
        "REPUBLIC",
        "PHILIPPINES",
        "PILIPINAS",
        "BARANGAY",
        "MUNICIPALITY",
        "CITY",
        "PROVINCE",
        "OFFICE OF",
        "LOCAL GOVERNMENT",
        "PUNONG BARANGAY",
        "CHAIRMAN",
        "VETERINARIAN",
        "VETERINARY",
        "TREASURER",
        "SECRETARY",
        "LGU",
        "SEAL",
      ];

      // 2. Document-Specific Indicators
      List<String> typeSpecificKeywords = [];
      final normalizedType = documentType.toLowerCase();

      if (normalizedType.contains("barangay")) {
        typeSpecificKeywords = [
          "BARANGAY",
          "PUNONG BARANGAY",
          "CHAIRMAN",
          "RESIDENT",
          "RESIDENCY",
          "BONAFIDE",
          "BONA-FIDE",
          "CLEARANCE",
          "ZONE",
          "DISTRICT",
        ];
      } else if (normalizedType.contains("business")) {
        typeSpecificKeywords = [
          "BUSINESS",
          "PERMIT",
          "CLEARANCE",
          "LICENSE",
          "COMMERCIAL",
          "OPERATING",
          "MAYOR",
          "FURNITURE",
          "ESTABLISHMENT",
          "STALL",
        ];
      } else if (normalizedType.contains("ownership")) {
        typeSpecificKeywords = [
          "OWNERSHIP",
          "CATTLE",
          "CATTLES",
          "LIVESTOCK",
          "ANIMAL",
          "BRAND",
          "BREED",
          "TRANSFER",
          "TREASURER",
          "CREDENTIAL",
          "DEED",
          "SALE",
          "REGISTRATION",
        ];
      } else if (normalizedType.contains("health") || normalizedType.contains("vet")) {
        typeSpecificKeywords = [
          "VETERINARY",
          "VETERINARIAN",
          "HEALTH",
          "EXAMINED",
          "ANIMAL",
          "DISEASE",
          "VET",
          "PRC",
          "SPECIES",
          "INSPECTION",
        ];
      }

      // Check matches
      final matchedCert = certKeywords.where((k) => fullText.contains(k)).toList();
      final matchedAuthority = authorityKeywords.where((k) => fullText.contains(k)).toList();
      final matchedSpecific = typeSpecificKeywords.where((k) => fullText.contains(k)).toList();

      final Set<String> allMatches = {
        ...matchedCert,
        ...matchedAuthority,
        ...matchedSpecific,
      };

      debugPrint("OCR Matched keywords: $allMatches");

      // Evaluation Logic:
      // Valid if:
      // - Has certificate term (or specific type match) AND has authority/government term
      // - OR has at least 2 type-specific terms
      final bool hasCertTerm = matchedCert.isNotEmpty;
      final bool hasAuthorityTerm = matchedAuthority.isNotEmpty;
      final bool hasSpecificMatch = matchedSpecific.length >= 2 || (hasCertTerm && matchedSpecific.isNotEmpty);

      if ((hasCertTerm && hasAuthorityTerm) || hasSpecificMatch) {
        return DocumentVerificationResult(
          isValid: true,
          message: "Document successfully verified as a valid $documentType.",
          detectedKeywords: allMatches.toList(),
          extractedSnippet: fullText.length > 150 ? fullText.substring(0, 150) : fullText,
        );
      }

      // If text exists but neither certificate nor official authority is detected
      return DocumentVerificationResult(
        isValid: false,
        message:
            "This image does not contain official certificate details for $documentType. Please make sure the entire document, official header, and seal are clearly visible and well-lit.",
        detectedKeywords: allMatches.toList(),
        extractedSnippet: fullText.length > 120 ? fullText.substring(0, 120) : fullText,
      );
    } catch (e) {
      debugPrint("Error performing OCR on document: $e");
      // If OCR engine encounters an unhandled platform error, allow user fallback
      return DocumentVerificationResult(
        isValid: true,
        message: "Scanned document accepted.",
        detectedKeywords: ["MANUAL_REVIEW"],
      );
    } finally {
      try {
        await textRecognizer.close();
      } catch (_) {}
    }
  }
}
