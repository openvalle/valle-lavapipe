// Loads the Vulkan loader by name, as wgpu does; creates an instance and a device on the
// llvmpipe CPU device; then compiles a compute shader, which lavapipe JIT-compiles with LLVM, runs
// it over 256 invocations and checks every result: the driver loads, compiles and executes.
// With --direct DRIVER, it loads the driver itself and calls it without any loader, as Valle
// does: no environment, manifest or registry is read, so this works in elevated processes too.
#define VK_NO_PROTOTYPES
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define LIBNAME "vulkan-1.dll"
#else
#include <dlfcn.h>
#define LIBNAME "libvulkan.so.1"
#endif

#include "probe.spv.h"

#define N 256
#ifdef _WIN32
static int require_packaged_module(HMODULE module, const char *name) {
  char actual[32768], expected[32768];
  DWORD n = GetModuleFileNameA(NULL, expected, sizeof(expected));
  if (!module || n == 0 || n >= sizeof(expected)) return 0;
  char *base = strrchr(expected, '\\');
  if (!base || (size_t)(base + 1 - expected) + strlen(name) >= sizeof(expected)) return 0;
  strcpy(base + 1, name);
  n = GetModuleFileNameA(module, actual, sizeof(actual));
  if (n == 0 || n >= sizeof(actual)) return 0;
  if (_stricmp(actual, expected) != 0) {
    fprintf(stderr, "loaded %s from %s, expected %s\n", name, actual, expected);
    return 0;
  }
  printf("loaded: %s\n", actual);
  return 1;
}
#endif

#define CHECK(call)                                                                            \
  do {                                                                                         \
    VkResult r_ = (call);                                                                      \
    if (r_ != VK_SUCCESS) {                                                                    \
      fprintf(stderr, "%s failed: %d\n", #call, r_);                                           \
      return 1;                                                                                \
    }                                                                                          \
  } while (0)
#define LOAD(name) PFN_##name name = (PFN_##name)gipa(inst, #name)

typedef VkResult(VKAPI_PTR *PFN_negotiate)(uint32_t *version);

// The driver's own entry point, after the interface negotiation the loader would do.
static PFN_vkGetInstanceProcAddr load_driver(const char *path) {
#ifdef _WIN32
  HMODULE lib = LoadLibraryA(path);
  if (!lib) {
    fprintf(stderr, "LoadLibrary %s failed: %lu\n", path, GetLastError());
    return NULL;
  }
#define SYM(name) GetProcAddress(lib, name)
#else
  void *lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    fprintf(stderr, "dlopen %s: %s\n", path, dlerror());
    return NULL;
  }
#define SYM(name) dlsym(lib, name)
#endif
  PFN_negotiate negotiate = (PFN_negotiate)SYM("vk_icdNegotiateLoaderICDInterfaceVersion");
  PFN_vkGetInstanceProcAddr gipa = (PFN_vkGetInstanceProcAddr)SYM("vk_icdGetInstanceProcAddr");
#undef SYM
  uint32_t version = 5;
  if (!negotiate || !gipa || negotiate(&version) != VK_SUCCESS) {
    fprintf(stderr, "%s is not a Vulkan driver of interface version 5\n", path);
    return NULL;
  }
  printf("driver: %s, interface version %u\n", path, version);
  return gipa;
}

// Whether the Vulkan loader is in the process: direct use must not bring it in.
static int loader_loaded(void) {
#ifdef _WIN32
  return GetModuleHandleA(LIBNAME) != NULL;
#else
  return dlopen(LIBNAME, RTLD_NOW | RTLD_NOLOAD) != NULL;
#endif
}

static PFN_vkGetInstanceProcAddr load_vulkan(void) {
#ifdef _WIN32
  HMODULE lib = LoadLibraryA(LIBNAME);
  if (!lib) {
    fprintf(stderr, "LoadLibrary %s failed: %lu\n", LIBNAME, GetLastError());
    return NULL;
  }
  if (!require_packaged_module(lib, LIBNAME)) return NULL;
  return (PFN_vkGetInstanceProcAddr)GetProcAddress(lib, "vkGetInstanceProcAddr");
#else
  void *lib = dlopen(LIBNAME, RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    fprintf(stderr, "dlopen %s: %s\n", LIBNAME, dlerror());
    return NULL;
  }
  return (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
#endif
}

int main(int argc, char **argv) {
  const char *direct = NULL;
  if (argc == 3 && strcmp(argv[1], "--direct") == 0) {
    direct = argv[2];
  } else if (argc != 1) {
    fprintf(stderr, "usage: %s [--direct DRIVER]\n", argv[0]);
    return 2;
  }
  PFN_vkGetInstanceProcAddr gipa = direct ? load_driver(direct) : load_vulkan();
  if (!gipa) {
    fprintf(stderr, "failed to load vkGetInstanceProcAddr\n");
    return 1;
  }
  VkInstance inst = VK_NULL_HANDLE;
  uint32_t api = VK_API_VERSION_1_0;
  LOAD(vkEnumerateInstanceVersion);
  if (vkEnumerateInstanceVersion) CHECK(vkEnumerateInstanceVersion(&api));
  printf("%s: Vulkan %u.%u.%u\n", direct ? "instance" : "loader", VK_API_VERSION_MAJOR(api),
         VK_API_VERSION_MINOR(api), VK_API_VERSION_PATCH(api));

  LOAD(vkCreateInstance);
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                           .pApplicationName = "valle-probe",
                           .apiVersion = VK_API_VERSION_1_3};
  VkInstanceCreateInfo ici = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                              .pApplicationInfo = &app};
  CHECK(vkCreateInstance(&ici, NULL, &inst));

  LOAD(vkEnumeratePhysicalDevices);
  LOAD(vkGetPhysicalDeviceProperties);
  LOAD(vkGetPhysicalDeviceMemoryProperties);
  LOAD(vkCreateDevice);
  LOAD(vkDestroyDevice);
  LOAD(vkDestroyInstance);
  LOAD(vkGetDeviceQueue);
  LOAD(vkCreateBuffer);
  LOAD(vkDestroyBuffer);
  LOAD(vkGetBufferMemoryRequirements);
  LOAD(vkAllocateMemory);
  LOAD(vkFreeMemory);
  LOAD(vkBindBufferMemory);
  LOAD(vkMapMemory);
  LOAD(vkUnmapMemory);
  LOAD(vkCreateDescriptorSetLayout);
  LOAD(vkDestroyDescriptorSetLayout);
  LOAD(vkCreateDescriptorPool);
  LOAD(vkDestroyDescriptorPool);
  LOAD(vkAllocateDescriptorSets);
  LOAD(vkUpdateDescriptorSets);
  LOAD(vkCreatePipelineLayout);
  LOAD(vkDestroyPipelineLayout);
  LOAD(vkCreateShaderModule);
  LOAD(vkDestroyShaderModule);
  LOAD(vkCreateComputePipelines);
  LOAD(vkDestroyPipeline);
  LOAD(vkCreateCommandPool);
  LOAD(vkDestroyCommandPool);
  LOAD(vkAllocateCommandBuffers);
  LOAD(vkBeginCommandBuffer);
  LOAD(vkEndCommandBuffer);
  LOAD(vkCmdBindPipeline);
  LOAD(vkCmdBindDescriptorSets);
  LOAD(vkCmdDispatch);
  LOAD(vkQueueSubmit);
  LOAD(vkQueueWaitIdle);

  VkPhysicalDevice pd[8];
  uint32_t n = 8;
  VkResult r = vkEnumeratePhysicalDevices(inst, &n, pd);
  if ((r != VK_SUCCESS && r != VK_INCOMPLETE) || n == 0) {
    fprintf(stderr, "no physical devices (%d)\n", r);
    return 1;
  }
  uint32_t selected = UINT32_MAX;
  for (uint32_t i = 0; i < n; i++) {
    VkPhysicalDeviceProperties p;
    vkGetPhysicalDeviceProperties(pd[i], &p);
    printf("device %u: %s, type %d, Vulkan %u.%u.%u\n", i, p.deviceName, p.deviceType,
           VK_API_VERSION_MAJOR(p.apiVersion), VK_API_VERSION_MINOR(p.apiVersion),
           VK_API_VERSION_PATCH(p.apiVersion));
    if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU && strstr(p.deviceName, "llvmpipe")) {
      if (selected != UINT32_MAX) {
        fprintf(stderr, "multiple llvmpipe devices; cannot identify the packaged driver\n");
        return 1;
      }
      selected = i;
    }
  }
  if (selected == UINT32_MAX) {
    fprintf(stderr, "no llvmpipe CPU device\n");
    return 1;
  }
#ifdef _WIN32
  if (!direct && !require_packaged_module(GetModuleHandleA("vulkan_lvp.dll"), "vulkan_lvp.dll"))
    return 1;
#endif

  float priority = 1.0f;
  VkDeviceQueueCreateInfo q = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                               .queueFamilyIndex = 0,
                               .queueCount = 1,
                               .pQueuePriorities = &priority};
  VkDeviceCreateInfo dci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                            .queueCreateInfoCount = 1,
                            .pQueueCreateInfos = &q};
  VkDevice dev;
  CHECK(vkCreateDevice(pd[selected], &dci, NULL, &dev));
  VkQueue queue;
  vkGetDeviceQueue(dev, 0, 0, &queue);

  // One host-visible buffer: N uints, then N floats.
  VkDeviceSize size = 2 * N * 4;
  VkBufferCreateInfo bci = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                            .size = size,
                            .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                            .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
  VkBuffer buf;
  CHECK(vkCreateBuffer(dev, &bci, NULL, &buf));
  VkMemoryRequirements req;
  vkGetBufferMemoryRequirements(dev, buf, &req);
  VkPhysicalDeviceMemoryProperties mp;
  vkGetPhysicalDeviceMemoryProperties(pd[selected], &mp);
  uint32_t type = UINT32_MAX;
  VkMemoryPropertyFlags want =
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
    if ((req.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want) {
      type = i;
      break;
    }
  }
  if (type == UINT32_MAX) {
    fprintf(stderr, "no host-visible memory\n");
    return 1;
  }
  VkMemoryAllocateInfo mai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                              .allocationSize = req.size,
                              .memoryTypeIndex = type};
  VkDeviceMemory mem;
  CHECK(vkAllocateMemory(dev, &mai, NULL, &mem));
  CHECK(vkBindBufferMemory(dev, buf, mem, 0));

  VkDescriptorSetLayoutBinding binding = {.binding = 0,
                                          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                          .descriptorCount = 1,
                                          .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT};
  VkDescriptorSetLayoutCreateInfo dslci = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 1,
      .pBindings = &binding};
  VkDescriptorSetLayout dsl;
  CHECK(vkCreateDescriptorSetLayout(dev, &dslci, NULL, &dsl));
  VkDescriptorPoolSize ps = {.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1};
  VkDescriptorPoolCreateInfo dpci = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                                     .maxSets = 1,
                                     .poolSizeCount = 1,
                                     .pPoolSizes = &ps};
  VkDescriptorPool pool;
  CHECK(vkCreateDescriptorPool(dev, &dpci, NULL, &pool));
  VkDescriptorSetAllocateInfo dsai = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                                      .descriptorPool = pool,
                                      .descriptorSetCount = 1,
                                      .pSetLayouts = &dsl};
  VkDescriptorSet set;
  CHECK(vkAllocateDescriptorSets(dev, &dsai, &set));
  VkDescriptorBufferInfo dbi = {.buffer = buf, .offset = 0, .range = VK_WHOLE_SIZE};
  VkWriteDescriptorSet w = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                            .dstSet = set,
                            .descriptorCount = 1,
                            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                            .pBufferInfo = &dbi};
  vkUpdateDescriptorSets(dev, 1, &w, 0, NULL);

  VkPipelineLayoutCreateInfo plci = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                     .setLayoutCount = 1,
                                     .pSetLayouts = &dsl};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(dev, &plci, NULL, &layout));
  VkShaderModuleCreateInfo smci = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                   .codeSize = sizeof(probe_spv),
                                   .pCode = probe_spv};
  VkShaderModule module;
  CHECK(vkCreateShaderModule(dev, &smci, NULL, &module));
  VkComputePipelineCreateInfo cpci = {
      .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                .module = module,
                .pName = "main"},
      .layout = layout};
  VkPipeline pipeline;
  CHECK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipeline));

  VkCommandPoolCreateInfo cpi = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                 .queueFamilyIndex = 0};
  VkCommandPool cmdpool;
  CHECK(vkCreateCommandPool(dev, &cpi, NULL, &cmdpool));
  VkCommandBufferAllocateInfo cbai = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                                      .commandPool = cmdpool,
                                      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                                      .commandBufferCount = 1};
  VkCommandBuffer cmd;
  CHECK(vkAllocateCommandBuffers(dev, &cbai, &cmd));
  VkCommandBufferBeginInfo cbbi = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  CHECK(vkBeginCommandBuffer(cmd, &cbbi));
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
  vkCmdDispatch(cmd, N / 64, 1, 1);
  CHECK(vkEndCommandBuffer(cmd));
  VkSubmitInfo si = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                     .commandBufferCount = 1,
                     .pCommandBuffers = &cmd};
  CHECK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
  CHECK(vkQueueWaitIdle(queue));

  void *mapped;
  CHECK(vkMapMemory(dev, mem, 0, size, 0, &mapped));
  const uint32_t *u = mapped;
  int bad = 0;
  for (uint32_t i = 0; i < N; i++) {
    float f;
    memcpy(&f, (const char *)mapped + 4 * (N + i), 4);
    float want_f = sinf((float)i * 0.01f);
    // Vulkan's bound for sin on [-pi, pi] is 2^-11; a broken JIT gives garbage, zeros or NaN.
    if (u[i] != i * i + 7 || !isfinite(f) || fabsf(f - want_f) > 4.9e-4f) {
      if (bad++ < 4) fprintf(stderr, "result %u: %u %g, want %u %g\n", i, u[i], f, i * i + 7, want_f);
    }
  }
  vkUnmapMemory(dev, mem);
  if (bad) {
    fprintf(stderr, "compute: %d of %d results wrong\n", bad, N);
    return 1;
  }
  if (direct && loader_loaded()) {
    fprintf(stderr, "the Vulkan loader was loaded, though the driver was called directly\n");
    return 1;
  }
  printf("ok: compute shader compiled, ran %d invocations, every result checked\n", N);

  vkDestroyCommandPool(dev, cmdpool, NULL);
  vkDestroyPipeline(dev, pipeline, NULL);
  vkDestroyShaderModule(dev, module, NULL);
  vkDestroyPipelineLayout(dev, layout, NULL);
  vkDestroyDescriptorPool(dev, pool, NULL);
  vkDestroyDescriptorSetLayout(dev, dsl, NULL);
  vkFreeMemory(dev, mem, NULL);
  vkDestroyBuffer(dev, buf, NULL);
  vkDestroyDevice(dev, NULL);
  vkDestroyInstance(inst, NULL);
  return 0;
}
