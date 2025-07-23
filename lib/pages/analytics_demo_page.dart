import 'package:flutter/material.dart';
import 'package:app/services/analytics_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsDemoPage extends StatefulWidget {
  const AnalyticsDemoPage({super.key});

  @override
  State<AnalyticsDemoPage> createState() => _AnalyticsDemoPageState();
}

class _AnalyticsDemoPageState extends State<AnalyticsDemoPage> {
  final TextEditingController _eventNameController = TextEditingController();
  final TextEditingController _paramKeyController = TextEditingController();
  final TextEditingController _paramValueController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _userRoleController = TextEditingController();
  
  final Map<String, dynamic> _eventParameters = {};
  bool _analyticsEnabled = true;

  @override
  void initState() {
    super.initState();
    // 记录页面访问
    AnalyticsService.logScreenView(
      screenName: 'Analytics演示页面',
      screenClass: 'AnalyticsDemoPage',
    );
  }

  void _addParameter() {
    final key = _paramKeyController.text.trim();
    final value = _paramValueController.text.trim();
    
    if (key.isNotEmpty && value.isNotEmpty) {
      setState(() {
        _eventParameters[key] = value;
        _paramKeyController.clear();
        _paramValueController.clear();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加参数: $key = $value')),
      );
    }
  }

  void _clearParameters() {
    setState(() {
      _eventParameters.clear();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除所有参数')),
    );
  }

  Future<void> _logCustomEvent() async {
    final eventName = _eventNameController.text.trim();
    
    if (eventName.isNotEmpty) {
      await AnalyticsService.logEvent(
        name: eventName,
        parameters: _eventParameters.isNotEmpty ? _eventParameters : null,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录事件: $eventName')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入事件名称')),
      );
    }
  }

  Future<void> _logPredefinedEvent(String eventType) async {
    switch (eventType) {
      case 'login':
        await AnalyticsService.logLogin(loginMethod: 'demo');
        break;
      case 'signup':
        await AnalyticsService.logSignUp(signUpMethod: 'demo');
        break;
      case 'search':
        await AnalyticsService.logSearch(searchTerm: '示例搜索');
        break;
      case 'view_content':
        await AnalyticsService.logViewContent(
          contentType: 'article',
          itemId: 'demo_article_123',
          itemName: '示例文章',
        );
        break;
      case 'add_to_cart':
        await AnalyticsService.logAddToCart(
          itemId: 'product_123',
          itemName: '示例商品',
          price: 99.9,
          quantity: 1,
        );
        break;
      case 'purchase':
        await AnalyticsService.logPurchase(
          transactionId: 'order_${DateTime.now().millisecondsSinceEpoch}',
          value: 99.9,
          items: [
            AnalyticsEventItem(
              itemId: 'product_123',
              itemName: '示例商品',
              price: 99.9,
              quantity: 1,
            ),
          ],
        );
        break;
      case 'error':
        await AnalyticsService.logAppError(
          errorCode: 'ERROR_DEMO',
          errorMessage: '示例错误',
        );
        break;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已记录预定义事件: $eventType')),
    );
  }

  Future<void> _setUserProperties() async {
    final userId = _userIdController.text.trim();
    final userRole = _userRoleController.text.trim();
    
    await AnalyticsService.setUserProperties(
      userID: userId.isNotEmpty ? userId : null,
      userRole: userRole.isNotEmpty ? userRole : null,
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已设置用户属性')),
    );
  }

  Future<void> _toggleAnalyticsCollection() async {
    setState(() {
      _analyticsEnabled = !_analyticsEnabled;
    });
    
    await AnalyticsService.setAnalyticsCollectionEnabled(_analyticsEnabled);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Analytics 数据收集已${_analyticsEnabled ? '启用' : '禁用'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Analytics 演示'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 预定义事件部分
            const Text(
              '预定义事件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('login'),
                  child: const Text('登录事件'),
                ),
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('signup'),
                  child: const Text('注册事件'),
                ),
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('search'),
                  child: const Text('搜索事件'),
                ),
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('view_content'),
                  child: const Text('内容查看'),
                ),
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('add_to_cart'),
                  child: const Text('加入购物车'),
                ),
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('purchase'),
                  child: const Text('购买事件'),
                ),
                ElevatedButton(
                  onPressed: () => _logPredefinedEvent('error'),
                  child: const Text('错误事件'),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // 自定义事件部分
            const Text(
              '自定义事件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _eventNameController,
              decoration: const InputDecoration(
                labelText: '事件名称',
                hintText: '例如: button_click, page_view',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // 参数部分
            const Text(
              '事件参数',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _paramKeyController,
                    decoration: const InputDecoration(
                      labelText: '参数名',
                      hintText: '例如: item_id',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _paramValueController,
                    decoration: const InputDecoration(
                      labelText: '参数值',
                      hintText: '例如: 123',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _addParameter,
                  child: const Text('添加参数'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _clearParameters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('清除参数'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_eventParameters.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前参数:'),
                    const SizedBox(height: 4),
                    ..._eventParameters.entries.map((entry) => Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    )),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _logCustomEvent,
              child: const Text('记录自定义事件'),
            ),
            
            const SizedBox(height: 24),
            
            // 用户属性部分
            const Text(
              '用户属性',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: '用户ID',
                hintText: '例如: user_123',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userRoleController,
              decoration: const InputDecoration(
                labelText: '用户角色',
                hintText: '例如: admin, user',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _setUserProperties,
              child: const Text('设置用户属性'),
            ),
            
            const SizedBox(height: 24),
            
            // 启用/禁用 Analytics
            const Text(
              'Analytics 设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('启用数据收集'),
              value: _analyticsEnabled,
              onChanged: (value) => _toggleAnalyticsCollection(),
            ),
            
            const SizedBox(height: 24),
            const Text(
              '注意事项:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. 事件数据通常需要 24 小时才能在 Firebase 控制台中显示\n'
              '2. 自定义事件名称不能以 firebase_, google_ 或 ga_ 开头\n'
              '3. 事件名称和参数名称只能包含字母、数字和下划线\n'
              '4. 每个应用最多支持 500 种不同的事件类型\n'
              '5. 用户属性用于用户分群分析，不应包含个人身份信息',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _paramKeyController.dispose();
    _paramValueController.dispose();
    _userIdController.dispose();
    _userRoleController.dispose();
    super.dispose();
  }
}