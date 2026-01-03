import os
import subprocess
import yaml
import json
import time

def get_audio_codec(filepath):
    """Extrae los codecs de audio únicos de las pistas seleccionadas (jpn, spa, eng)"""
    cmd = [
        'ffprobe', '-v', 'error', '-select_streams', 'a',
        '-show_entries', 'stream=codec_name:stream_tags=language', '-of', 'json', filepath
    ]
    target_langs = {'jpn', 'spa', 'eng'}
    try:
        result = subprocess.check_output(cmd).decode('utf-8')
        data = json.loads(result)
        
        unique_codecs = set()
        if 'streams' in data:
            for stream in data['streams']:
                # Obtener idioma, manejando posibles faltas de tags
                lang = stream.get('tags', {}).get('language', 'und')
                if lang in target_langs:
                    codec = stream.get('codec_name', 'unk').upper()
                    unique_codecs.add(codec)
        
        if not unique_codecs:
            return "UNK"
            
        return "+".join(sorted(unique_codecs))
    except Exception:
        return "UNK"

def get_video_tag(v_codec):
    """Mapea el nombre del encoder de la config a una etiqueta de archivo"""
    mapping = {
        "libx265": "HEVC",
        "libx264": "AVC",
        "libsvtav1": "AV1",
        "hevc_nvenc": "HEVC-NV"
    }
    return mapping.get(v_codec, v_codec.upper())

def process_files():
    # Asegurar que trabajamos en el directorio del script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    with open("config_encoding.yaml", "r") as f:
        cfg = yaml.safe_load(f)
    
    paths = cfg['paths']
    enc = cfg['encoding']
    
    os.makedirs(paths['input'], exist_ok=True)
    os.makedirs(paths['output'], exist_ok=True)

    files = [f for f in os.listdir(paths['input']) if f.endswith(('.mkv', '.mp4'))]
    
    for file_name in files:
        input_path = os.path.join(paths['input'], file_name)
        
        # 1. Analisis detallado del archivo
        probe_cmd = [
            'ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', input_path
        ]
        try:
            probe_data = json.loads(subprocess.check_output(probe_cmd).decode('utf-8'))
        except Exception as e:
            print(f"Error analizando {file_name}: {e}")
            continue

        audio_tracks = []
        subtitle_tracks = []
        video_codec_orig = "UNK"
        
        target_langs = {'jpn', 'spa', 'eng'}
        kept_audios = []
        kept_subtitles = []

        for stream in probe_data.get('streams', []):
            st_type = stream.get('codec_type')
            st_codec = stream.get('codec_name', 'unk')
            st_lang = stream.get('tags', {}).get('language', 'und')
            
            info = f"{st_type.upper()}: {st_codec} ({st_lang})"
            
            if st_type == 'video':
                video_codec_orig = st_codec
            
            elif st_type == 'audio':
                audio_tracks.append(info)
                if st_lang in target_langs:
                    kept_audios.append(f"{st_codec} ({st_lang})")
            
            elif st_type == 'subtitle':
                subtitle_tracks.append(info)
                if st_lang in target_langs or st_lang == 'und':
                    kept_subtitles.append(f"{st_lang}")

        # 2. Obtener tags para nombre (manteniendo logica anterior)
        audio_tag = get_audio_codec(input_path)
        video_tag = get_video_tag(enc['v_codec'])
        tag_completo = f"[{video_tag}-{audio_tag}]"
        new_name = f"{cfg['naming']['prefix']}{tag_completo} {file_name}"
        output_path = os.path.join(paths['output'], new_name)

        # 3. Reporte de Estado (JSON)
        status = {
            "status": "processing",
            "file": file_name,
            "original": {
                "video": video_codec_orig,
                "audios": audio_tracks,
                "subtitles": subtitle_tracks
            },
            "target": {
                "file": new_name,
                "video": enc['v_codec'],
                "keeping_audios": kept_audios,
                "keeping_subtitles": kept_subtitles
            },
            "timestamp": time.time()
        }
        
        with open("status.json", "w") as f:
            json.dump(status, f, indent=2)

        print(f"--- Procesando: {file_name} ---")
        print(f"Plan: {json.dumps(status['target'], indent=2)}")

        # 4. Comando FFmpeg
        cmd = [
            'ffmpeg', '-y', '-i', input_path,  # -y para sobreescribir si es necesario
            '-map', '0:v:0',
            '-c:v', enc['v_codec'], '-crf', str(enc['crf']),
            '-preset', enc['preset'], '-tune', enc['tune'], '-pix_fmt', enc['pix_fmt'],
            # Audios
            '-map', '0:a:m:language:jpn?', '-map', '0:a:m:language:spa?', '-map', '0:a:m:language:eng?',
            '-c:a', 'copy',
            # Subtítulos
            '-map', '0:s:m:language:jpn?', '-map', '0:s:m:language:spa?', 
            '-map', '0:s:m:language:eng?', '-map', '0:s:m:language:und?',
            '-c:s', 'copy',
            output_path
        ]

        print(f"--- Procesando: {file_name} ---")
        try:
            subprocess.run(cmd, check=True)
            print(f"--- Éxito: {new_name} ---")
            
            with open("status.json", "w") as f:
                json.dump({"status": "idle", "last_finished": file_name}, f, indent=2)
        except subprocess.CalledProcessError:
            print(f"Error crítico en: {file_name}")

if __name__ == "__main__":
    while True:
        process_files()
        time.sleep(15)