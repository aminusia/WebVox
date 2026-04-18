import 'package:web_reader/domain/entities/reading_state.dart';

abstract class ReadingStateRepository {
  Future<ReadingState?> getReadingState(String articleId);
  Future<void> saveReadingState(ReadingState state);
  Future<void> deleteReadingState(String articleId);
}
