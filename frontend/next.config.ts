import type { NextConfig } from "next";

const nextConfig: NextConfig = {
    allowedDevOrigins: ["192.168.1.3"],
    // RainbowKit's bundled Base Account connector pulls in @coinbase/cdp-sdk,
    // which has a dynamic Solana import Turbopack can't statically bundle for SSR.
    serverExternalPackages: ["@coinbase/cdp-sdk", "@base-org/account"],
};

export default nextConfig;
