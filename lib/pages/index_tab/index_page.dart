import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class IndexPage extends HookConsumerWidget {
  const IndexPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = useState<List<String>>([]);
    final page = useState<int>(0);
    final isLoading = useState<bool>(false);
    final hasMore = useState<bool>(true);
    final scrollController = useScrollController();

    Future<void> fetchMoreItems() async {
      if (isLoading.value || !hasMore.value) return;

      isLoading.value = true;
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));

      const itemsPerPage = 20;
      final newItems = List.generate(
        itemsPerPage,
        (i) => 'Item ${(page.value * itemsPerPage) + i + 1}',
      );

      items.value = [...items.value, ...newItems];
      page.value++;

      // Simulate end of data after 3 pages
      if (page.value >= 3) {
        hasMore.value = false;
      }
      isLoading.value = false;
    }

    useEffect(() {
      // Initial data load
      if (items.value.isEmpty) {
        // Fetch only if items list is empty
        fetchMoreItems();
      }

      void scrollListener() {
        // Check if near bottom and not loading and has more data
        if (scrollController.position.pixels >=
                scrollController.position.maxScrollExtent - 200 &&
            !isLoading.value &&
            hasMore.value) {
          fetchMoreItems();
        }
      }

      scrollController.addListener(scrollListener);
      // Cleanup: remove listener when widget is disposed or controller changes
      return () => scrollController.removeListener(scrollListener);
    }, [scrollController]); // Rerun effect if scrollController instance changes

    return Scaffold(
      appBar: AppBar(title: const Text('Infinite Scroll')),
      body: ListView.builder(
        controller: scrollController,
        itemCount:
            items.value.length + (isLoading.value || hasMore.value ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < items.value.length) {
            return ListTile(title: Text(items.value[index]));
          } else if (isLoading.value) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ),
            );
          } else if (!hasMore.value) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No more items'),
              ),
            );
          }
          // This placeholder is for the case when hasMore is true but not currently loading
          // It prevents null being returned if itemCount logic is slightly off during state transitions
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
