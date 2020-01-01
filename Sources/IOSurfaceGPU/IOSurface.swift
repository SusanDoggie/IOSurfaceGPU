//
//  IOSurface.swift
//
//  The MIT License
//  Copyright (c) 2015 - 2020 Susan Cheng. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Metal
@_exported import IOSurface

#if canImport(CoreImage)

import CoreImage

#endif

#if canImport(QuartzCore)

import QuartzCore

#endif

extension IOSurfaceRef {
    
    public var width: Int {
        return IOSurfaceGetWidth(self)
    }
    
    public var height: Int {
        return IOSurfaceGetHeight(self)
    }
    
    public var planeCount: Int {
        return IOSurfaceGetPlaneCount(self)
    }
    
    public var pixelFormat: OSType {
        return IOSurfaceGetPixelFormat(self)
    }
    
    @discardableResult
    public func lock(options: IOSurfaceLockOptions = [], seed: UnsafeMutablePointer<UInt32>?) -> kern_return_t {
        return IOSurfaceLock(self, options, seed)
    }
    
    @discardableResult
    public func unlock(options: IOSurfaceLockOptions = [], seed: UnsafeMutablePointer<UInt32>?) -> kern_return_t {
        return IOSurfaceUnlock(self, options, seed)
    }
}

extension IOSurfaceRef {
    
    private class BundleToken { }
    
    private static let library: Data = {
        do {
            guard let url = Bundle(for: BundleToken.self).url(forResource: "default", withExtension: "metallib") else { fatalError("IOSurface: Unable to get metallib") }
            return try Data(contentsOf: url, options: .alwaysMapped)
        } catch let error {
            fatalError("\(error)")
        }
    }()
    
    private static let AlphaMaskKernel: CIColorKernel = {
        do {
            return try CIColorKernel(functionName: "alpha_mask", fromMetalLibraryData: IOSurfaceRef.library)
        } catch let error {
            fatalError("\(error)")
        }
    }()
    
    public var ciImage: CIImage? {
        
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else { return nil }
        
        let format = withUnsafeBytes(of: (pixelFormat.bigEndian, 0 as UInt8)) { String(cString: $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        
        switch format {
            
        case "BGRA":        // BGRA
            
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            guard let texture = mtlDevice.makeTexture(descriptor: descriptor, iosurface: self, plane: 0) else { return nil }
            
            return CIImage(mtlTexture: texture)?.transformed(by: CGAffineTransform(scaleX: 1, y: -1)).transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)))
            
        case "w30r":        // RGB10
            
            #if os(iOS) || os(tvOS)
            
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgr10_xr_srgb, width: width, height: height, mipmapped: false)
            guard let texture = mtlDevice.makeTexture(descriptor: descriptor, iosurface: self, plane: 0) else { return nil }
            
            return CIImage(mtlTexture: texture)?.transformed(by: CGAffineTransform(scaleX: 1, y: -1)).transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)))
            
            #else
            
            return nil
            
            #endif
            
        case "b3a8":        // RGB10A8
            
            #if os(iOS) || os(tvOS)
            
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgr10_xr_srgb, width: width, height: height, mipmapped: false)
            guard let texture = mtlDevice.makeTexture(descriptor: descriptor, iosurface: self, plane: 0), let image = CIImage(mtlTexture: texture) else { return nil }
            
            let mask_descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .a8Unorm, width: width, height: height, mipmapped: false)
            guard let mask_texture = mtlDevice.makeTexture(descriptor: mask_descriptor, iosurface: self, plane: 1), let mask = CIImage(mtlTexture: mask_texture) else { return nil }
            
            return IOSurfaceRef.AlphaMaskKernel.apply(extent: image.extent, arguments: [image, mask])?.transformed(by: CGAffineTransform(scaleX: 1, y: -1)).transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)))
            
            #else
            
            return nil
            
            #endif
            
        default: return nil
        }
    }
}
