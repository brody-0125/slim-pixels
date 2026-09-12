use std::{ffi::{c_int,c_ulong,c_void,CStr},fs,io::Write,path::Path,ptr,slice,time::Instant,hint::black_box};
use image::{RgbImage,DynamicImage,ExtendedColorType,codecs::jpeg::JpegEncoder};
use fast_image_resize::{images::Image,PixelType,Resizer,ResizeOptions,ResizeAlg,FilterType};
use serde_json::{Value,json};

// Native unsigned long: 64-bit on Linux x86_64, 32-bit on Windows x64.
#[link(name="turbojpeg")]
unsafe extern "C" {
    fn tj3Set(handle:*mut c_void,param:c_int,value:c_int)->c_int;
    fn tjInitCompress()->*mut c_void;
    fn tjCompress2(handle:*mut c_void,src:*const u8,w:c_int,pitch:c_int,h:c_int,pixel:c_int,out:*mut *mut u8,len:*mut c_ulong,subsample:c_int,quality:c_int,flags:c_int)->c_int;
    fn tjDestroy(handle:*mut c_void)->c_int;
    fn tjFree(buffer:*mut u8);
    fn tjGetErrorStr2(handle:*mut c_void)->*const i8;
}
struct Native {handle:*mut c_void,output:*mut u8}
impl Drop for Native {fn drop(&mut self){unsafe{if !self.output.is_null(){tjFree(self.output)}if !self.handle.is_null(){tjDestroy(self.handle);}}}}
fn encode(raw:&RgbImage,q:u8,mode:&str)->Result<Vec<u8>,String>{
    if !mode.starts_with("turbo") {let mut out=Vec::new();JpegEncoder::new_with_quality(&mut out,q).encode(raw.as_raw(),raw.width(),raw.height(),ExtendedColorType::Rgb8).map_err(|e|e.to_string())?;return Ok(out)}
    unsafe {
        let mut n=Native{handle:tjInitCompress(),output:ptr::null_mut()};
        if n.handle.is_null(){return Err("tjInitCompress failed".into())}
        if mode=="turbo_opt" && tj3Set(n.handle,11,1)!=0 {return Err("tj3Set optimize failed".into())}
        let mut len:c_ulong=0;
        let code=tjCompress2(n.handle,raw.as_raw().as_ptr(),raw.width() as i32,0,raw.height() as i32,0,&mut n.output,&mut len,0,q as i32,4096);
        if code!=0 {return Err(CStr::from_ptr(tjGetErrorStr2(n.handle)).to_string_lossy().into_owned())}
        if n.output.is_null() || len==0{return Err("empty output".into())}
        Ok(slice::from_raw_parts(n.output,len as usize).to_vec())
    }
}
fn decode(bytes:&[u8])->Result<RgbImage,String>{
    let img=image::load_from_memory(bytes).map_err(|e|e.to_string())?;
    if let DynamicImage::ImageRgb8(rgb)=img {return Ok(rgb)}
    let rgba=img.into_rgba8();
    Ok(RgbImage::from_fn(rgba.width(),rgba.height(),|x,y|{let p=rgba.get_pixel(x,y).0;let a=u32::from(p[3]);image::Rgb([0,1,2].map(|c|((u32::from(p[c])*a+255*(255-a)+127)/255)as u8))}))
}
fn resize(src:&RgbImage,bound:u32)->Result<RgbImage,String>{
    let scale=(bound as f64/src.width() as f64).min(bound as f64/src.height() as f64).min(1.);
    let(w,h)=((src.width() as f64*scale).round() as u32,(src.height() as f64*scale).round() as u32);
    let mut dst=Image::new(w,h,PixelType::U8x3);
    let options=ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Lanczos3)).use_alpha(false);
    Resizer::new().resize(src,&mut dst,&options).map_err(|e|e.to_string())?;
    RgbImage::from_raw(w,h,dst.into_vec()).ok_or("bad output layout".into())
}
fn metrics(a:&[u8],b:&[u8])->Value{
    assert_eq!(a.len(),b.len());let(mut max,mut abs,mut sq,mut changed)=(0u8,0u64,0u64,0usize);
    for(x,y)in a.iter().zip(b){let d=x.abs_diff(*y);max=max.max(d);abs+=d as u64;sq+=(d as u64)*(d as u64);changed+=usize::from(d!=0);}
    json!({"exact":a==b,"max":max,"mae":abs as f64/a.len() as f64,"changed_channels":changed,"psnr":if sq==0 {None}else{Some(10.*(65025./(sq as f64/a.len() as f64)).log10())}})
}
fn shuffle(v:&mut[&str],seed:&mut u32){for i in(1..v.len()).rev(){*seed^=*seed<<13;*seed^=*seed>>17;*seed^=*seed<<5;v.swap(i,*seed as usize%(i+1));}}
fn main()->Result<(),Box<dyn std::error::Error>>{
    let args:Vec<_>=std::env::args().collect();let root=Path::new(&args[1]);let trial:u32=args[3].parse()?;
    let mut out=fs::File::create(&args[2])?;let mut seed=58137+trial;
    let manifest:Vec<Value>=serde_json::from_slice(&fs::read(root.join("manifest.json"))?)?;
    let saved=root.join("encoded");let raws=root.join("raw");fs::create_dir_all(&saved)?;fs::create_dir_all(&raws)?;
    for item in manifest {
        let file=item["file"].as_str().unwrap();let input=fs::read(root.join("corpus").join(file))?;let decoded=decode(&input)?;
        for bound in [512,1600] {
            let raw=resize(&decoded,bound)?;let id=format!("{file}__{bound}");
            if trial==1 {fs::write(raws.join(format!("{id}.rgb")),raw.as_raw())?;}
            for q in [75u8,90,95] {
                let reference=encode(&raw,q,"baseline")?;let ref_decoded=image::load_from_memory(&reference)?.into_rgb8();
                for mode in ["baseline","aa","turbo","turbo_opt"] {
                    let encoded=encode(&raw,q,mode)?;let restored=image::load_from_memory(&encoded)?.into_rgb8();assert_eq!(restored.dimensions(),raw.dimensions());
                    if mode=="aa"{assert_eq!(encoded,reference)}
                    if mode=="turbo_opt" {let plain=encode(&raw,q,"turbo")?;let plain_decoded=image::load_from_memory(&plain)?.into_rgb8();assert_eq!(restored,plain_decoded,"Huffman optimization changed decoded pixels");}
                    if trial==1 && mode!="aa"{fs::write(saved.join(format!("{id}__q{q}__{mode}.jpg")),&encoded)?;}
                    writeln!(out,"{}",json!({"type":"quality","file":file,"bound":bound,"quality":q,"mode":mode,"width":raw.width(),"height":raw.height(),"bytes":encoded.len(),"raw_error":metrics(raw.as_raw(),restored.as_raw()),"baseline_error":metrics(ref_decoded.as_raw(),restored.as_raw()),"encoded_exact":encoded==reference}))?;
                }
                for round in 0..9 {let mut modes=["baseline","aa","turbo","turbo_opt"];shuffle(&mut modes,&mut seed);
                    for mode in modes {let t=Instant::now();let encoded=encode(black_box(&raw),q,mode)?;black_box(&encoded);let ms=t.elapsed().as_secs_f64()*1000.;
                        if round>=2{writeln!(out,"{}",json!({"type":"time","trial":trial,"file":file,"bound":bound,"quality":q,"mode":mode,"stage":"encode","round":round-2,"ms":ms}))?;}
                    }
                }
            }
        }
        drop(decoded);
        for round in 0..9 {let mut modes=["baseline","aa","turbo","turbo_opt"];shuffle(&mut modes,&mut seed);
            for mode in modes {let t=Instant::now();let src=decode(black_box(&input))?;let raw=resize(&src,1600)?;drop(src);let encoded=encode(&raw,90,mode)?;black_box(&encoded);let ms=t.elapsed().as_secs_f64()*1000.;
                if round>=2{writeln!(out,"{}",json!({"type":"time","trial":trial,"file":file,"bound":1600,"quality":90,"mode":mode,"stage":"pipeline","round":round-2,"ms":ms}))?;}
            }
        }out.flush()?;
    }
    Ok(())
}
