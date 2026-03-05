{
  # Kubernetes PriorityClasses for workload prioritization
  kubernetes.resources.priorityClasses = {
    high-priority = {
      metadata.name = "high-priority";
      value = 1000000;
      globalDefault = false;
      description = "Critical services that must not be preempted";
    };
    medium-priority = {
      metadata.name = "medium-priority";
      value = 100000;
      globalDefault = true;
      description = "Standard workloads";
    };
    low-priority = {
      metadata.name = "low-priority";
      value = 10000;
      globalDefault = false;
      description = "Batch jobs and non-critical services";
    };
  };
}
