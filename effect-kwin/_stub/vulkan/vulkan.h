/* Stub de compilacion. NO es el Vulkan real.
   Existe solo para que find_package(Vulkan) de KWinConfig no falle.
   El efecto macosglass no incluye ni usa Vulkan. */
#ifndef VULKAN_STUB_H
#define VULKAN_STUB_H
#define VK_API_VERSION_1_0 4194304
#define VK_MAKE_VERSION(a,b,c) 0
#define VK_API_VERSION_MAJOR(v) 1
#define VK_API_VERSION_MINOR(v) 0
#endif
