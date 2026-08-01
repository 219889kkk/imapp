import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:openim_common/openim_common.dart';
import 'package:flutter_map/flutter_map.dart';

class LocationPickerResult {
  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.description,
  });

  final double latitude;
  final double longitude;
  final String description;
}

class LocationPickerView extends StatefulWidget {
  const LocationPickerView({super.key});

  @override
  State<LocationPickerView> createState() => _LocationPickerViewState();
}

class _LocationPickerViewState extends State<LocationPickerView> {
  final descCtrl = TextEditingController();
  Position? position;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      var enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        IMViews.showToast(StrRes.permissionDeniedTitle);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        IMViews.showToast(StrRes.permissionDeniedTitle);
        return;
      }
      final value = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        position = value;
        descCtrl.text =
            '${value.latitude.toStringAsFixed(6)}, ${value.longitude.toStringAsFixed(6)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = position;
    return Scaffold(
      appBar: TitleBar.back(
        title: StrRes.location,
        right: StrRes.confirm.toText
          ..style = Styles.ts_0089FF_17sp
          ..onTap = pos == null ? null : _submit,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : pos == null
              ? Center(
                  child: StrRes.permissionDeniedTitle.toText
                    ..style = Styles.ts_8E9AB0_17sp,
                )
              : Column(
                  children: [
                    Expanded(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(pos.latitude, pos.longitude),
                          initialZoom: 15,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                            userAgentPackageName: '',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(pos.latitude, pos.longitude),
                                child: Icon(
                                  Icons.location_on_sharp,
                                  color: Styles.c_FF381F,
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: Styles.c_FFFFFF,
                      padding: EdgeInsets.all(16.w),
                      child: TextField(
                        controller: descCtrl,
                        decoration: InputDecoration(
                          hintText: StrRes.location,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _submit() {
    final pos = position;
    if (pos == null) return;
    Navigator.of(context).pop(LocationPickerResult(
      latitude: pos.latitude,
      longitude: pos.longitude,
      description: descCtrl.text.trim(),
    ));
  }
}
