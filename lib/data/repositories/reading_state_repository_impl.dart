import 'package:webvox/data/sources/local/local_reading_state_source.dart';
import 'package:webvox/domain/entities/reading_state.dart';
import 'package:webvox/domain/repositories/reading_state_repository.dart';

class ReadingStateRepositoryImpl implements ReadingStateRepository {
  final LocalReadingStateSource _source;

  ReadingStateRepositoryImpl({LocalReadingStateSource? source})
    : _source = source ?? LocalReadingStateSource();

  @override
  Future<ReadingState?> getReadingState(String articleId) =>
      _source.get(articleId);

  @override
  Future<void> saveReadingState(ReadingState state) => _source.save(state);

  @override
  Future<void> deleteReadingState(String articleId) =>
      _source.delete(articleId);
}
