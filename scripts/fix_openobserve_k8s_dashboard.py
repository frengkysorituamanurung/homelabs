import json
import urllib.request
import base64

url = "https://openobserve.frengky.xyz/api/default/dashboards"
auth_header = "Basic " + base64.b64encode(b"admin@frengky.xyz:REPLACE_WITH_OPENOBSERVE_PASSWORD").decode()

dashboard_payload = {
    "title": "Kubernetes / Namespace (Pods)",
    "dashboardId": "7489378957897236480",
    "description": "Pod metrics per namespace (Prometheus Powered)",
    "variables": {
        "list": [
            {
                "type": "query_values",
                "name": "namespace",
                "label": "Namespace",
                "query_data": {
                    "stream_type": "metrics",
                    "stream": "container_memory_rss",
                    "field": "namespace",
                    "max_record_size": None,
                    "filter": []
                },
                "value": "monitoring",
                "options": [],
                "multiSelect": False,
                "hideOnDashboard": False,
                "selectAllValueForMultiSelect": "first",
                "customMultiSelectValue": []
            }
        ],
        "showDynamicFilters": True
    },
    "tabs": [
        {
            "tabId": "default",
            "name": "Overview",
            "panels": [
                {
                    "id": "panel_cpu_usage",
                    "type": "area-stacked",
                    "title": "CPU Usage (Cores) per Pod",
                    "description": "CPU usage in cores per pod in selected namespace",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "unit": "short",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (rate(container_cpu_usage_seconds_total{container!=\"\", namespace=~\"$namespace\"}[5m]))",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "container_cpu_usage_seconds_total",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_memory_usage",
                    "type": "area-stacked",
                    "title": "Memory Usage (RSS) per Pod",
                    "description": "Memory usage in bytes per pod",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "unit": "bytes",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (container_memory_rss{container!=\"\", namespace=~\"$namespace\"})",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "container_memory_rss",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_net_rx",
                    "type": "line",
                    "title": "Network Receive Bandwidth",
                    "description": "Network bytes received per second per pod",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "unit": "bytes/sec",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (rate(container_network_receive_bytes_total{namespace=~\"$namespace\"}[5m]))",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "container_network_receive_bytes_total",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_net_tx",
                    "type": "line",
                    "title": "Network Transmit Bandwidth",
                    "description": "Network bytes transmitted per second per pod",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "unit": "bytes/sec",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (rate(container_network_transmit_bytes_total{namespace=~\"$namespace\"}[5m]))",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "container_network_transmit_bytes_total",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_pvc_usage",
                    "type": "bar",
                    "title": "Storage: PVC Usage (%)",
                    "description": "Percentage of persistent volume capacity used",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "unit": "percent",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "(sum by (persistentvolumeclaim) (kubelet_volume_stats_used_bytes{namespace=~\"$namespace\"}) / sum by (persistentvolumeclaim) (kubelet_volume_stats_capacity_bytes{namespace=~\"$namespace\"})) * 100",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "kubelet_volume_stats_used_bytes",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{persistentvolumeclaim}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_iops",
                    "type": "line",
                    "title": "Storage: Disk IOPS (Read + Write)",
                    "description": "IO operations per second per pod",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (rate(container_fs_reads_total{container!=\"\", namespace=~\"$namespace\"}[5m]) + rate(container_fs_writes_total{container!=\"\", namespace=~\"$namespace\"}[5m]))",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "container_fs_reads_total",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_throughput",
                    "type": "line",
                    "title": "Storage: Throughput (Read + Write)",
                    "description": "Disk read and write throughput in bytes/sec",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "unit": "bytes/sec",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (rate(container_fs_reads_bytes_total{container!=\"\", namespace=~\"$namespace\"}[5m]) + rate(container_fs_writes_bytes_total{container!=\"\", namespace=~\"$namespace\"}[5m]))",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "container_fs_reads_bytes_total",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                },
                {
                    "id": "panel_restarts",
                    "type": "bar",
                    "title": "Pod Container Restarts (Last 1h)",
                    "description": "Number of restarts per pod container",
                    "config": {
                        "show_legends": True,
                        "legends_position": "right",
                        "base_map": None,
                        "map_view": None
                    },
                    "queryType": "promql",
                    "queries": [
                        {
                            "query": "sum by (pod) (changes(kube_pod_container_status_restarts_total{namespace=~\"$namespace\"}[1h]))",
                            "vrlFunctionQuery": "",
                            "customQuery": True,
                            "fields": {
                                "stream": "kube_pod_container_status_restarts_total",
                                "stream_type": "metrics",
                                "x": [],
                                "y": [],
                                "z": [],
                                "breakdown": [],
                                "filter": {
                                    "filterType": "group",
                                    "logicalOperator": "AND",
                                    "conditions": []
                                }
                            },
                            "config": {
                                "promql_legend": "{pod}",
                                "layer_type": "scatter",
                                "weight_fixed": 1.0
                            }
                        }
                    ]
                }
            ]
        }
    ]
}

req = urllib.request.Request(
    url,
    data=json.dumps(dashboard_payload).encode("utf-8"),
    headers={"Content-Type": "application/json", "Authorization": auth_header},
    method="POST"
)

try:
    with urllib.request.urlopen(req) as resp:
        print("Status Code:", resp.status)
        print("Body:", resp.read().decode())
except urllib.error.HTTPError as e:
    print("HTTP Error:", e.code, e.read().decode())
except Exception as e:
    print("Error:", e)
