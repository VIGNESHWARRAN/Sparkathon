// lib/features/circle_search/circle_search_page.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

final logger = Logger();

class CircleSearchPage extends StatefulWidget {
  const CircleSearchPage({super.key});

  @override
  State<CircleSearchPage> createState() => _CircleSearchPageState();
}

class _CircleSearchPageState extends State<CircleSearchPage> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String? _error;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  Future<void> _startSearch() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) {
      setState(() {
        _error = "No image selected.";
        _loading = false;
      });
      return;
    }

    _pickedImage = File(pickedFile.path);
    logger.d("Picked image path: ${_pickedImage!.path}");

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'http://192.168.0.106:8000/circle_search',
        ),
      );

      request.files.add(
        await http.MultipartFile.fromPath('file', _pickedImage!.path),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final results = (data['results'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        setState(() {
          _results = results;
          _loading = false;
        });
      } else {
        setState(() {
          _error = "Server error: ${response.statusCode}";
          _loading = false;
        });
      }
    } catch (e, st) {
      logger.e("Request failed", error: e, stackTrace: st);
      setState(() {
        _error = "Failed to connect to server.";
        _loading = false;
      });
    }
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating.floor() ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 16,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Circle Search")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                if (_pickedImage != null)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Your Selected Image",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _pickedImage!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(thickness: 1),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Top 5 Similar Products",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final imageUrl =
                          item["image_url"]
                              ?.toString()
                              .replaceAll('"', '')
                              .trim() ??
                          "";
                      Map<String, dynamic>? ratingStars;
                      try {
                        final rawRating = item["rating_stars"];
                        if (rawRating is String) {
                          ratingStars = Map<String, dynamic>.from(
                            json.decode(rawRating),
                          );
                        } else if (rawRating is Map) {
                          ratingStars = Map<String, dynamic>.from(rawRating);
                        }
                      } catch (e) {
                        logger.e("Failed to parse rating_stars", error: e);
                      }
                      // Calculate average rating and total reviews
                      String ratingText = "No ratings yet";
                      Color ratingColor = const Color.fromARGB(
                        255,
                        255,
                        251,
                        1,
                      );
                      double averageRating = 0;
                      int totalRatings = 0;

                      if (ratingStars != null) {
                        totalRatings = ratingStars.values.fold(
                          0,
                          (sum, count) => sum + (count is int ? count : 0),
                        );
                        if (totalRatings > 0) {
                          averageRating =
                              (5 * (ratingStars["five_stars"] ?? 0) +
                                  4 * (ratingStars["four_stars"] ?? 0) +
                                  3 * (ratingStars["three_stars"] ?? 0) +
                                  2 * (ratingStars["two_stars"] ?? 0) +
                                  1 * (ratingStars["one_star"] ?? 0)) /
                              totalRatings;

                          // Set rating text and color based on average
                          ratingText =
                              "★ ${averageRating.toStringAsFixed(1)} ($totalRatings)";
                          ratingColor = averageRating >= 4
                              ? Colors.green
                              : averageRating >= 3
                              ? Colors.orange
                              : Colors.red;
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(8),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                                progress.expectedTotalBytes!
                                          : null,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                logger.e(
                                  "Image load failed: $error\nURL: $imageUrl",
                                );
                                return Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 30,
                                  ),
                                );
                              },
                            ),
                          ),
                          title: Text(
                            item["name"]?.toString() ?? "Unnamed Product",
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "₹${item["price"]?.toString() ?? "N/A"}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    ratingText,
                                    style: TextStyle(
                                      color: ratingColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (totalRatings > 0) ...[
                                    const SizedBox(width: 8),
                                    _buildStarRating(averageRating),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
