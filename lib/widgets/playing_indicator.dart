import 'package:flutter/material.dart';

class PlayingIndicator extends StatefulWidget {
  final Color? color;
  final double size;
  
  const PlayingIndicator({
    super.key,
    this.color,
    this.size = 16.0,
  });

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          final delay = index * 0.15;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final animValue = (_controller.value + delay) % 1.0;
              final height = widget.size * (0.3 + 0.7 * (1 - (animValue - 0.5).abs() * 2));
              return Container(
                width: widget.size / 5,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(widget.size / 10),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
