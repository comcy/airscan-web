#!/usr/bin/env python3
"""Generate PWA icons from emoji or simple graphics"""
from PIL import Image, ImageDraw, ImageFont
import os

def create_icon(size, output_path):
    """Create a simple scanner icon"""
    # Create image with gradient background
    img = Image.new('RGB', (size, size), color='#667eea')
    draw = ImageDraw.Draw(img)
    
    # Draw a simple printer/scanner shape
    margin = size // 6
    
    # Printer body (rectangle)
    body_top = size // 3
    body_bottom = size - margin
    draw.rectangle(
        [margin, body_top, size - margin, body_bottom],
        fill='white',
        outline='#333333',
        width=max(2, size // 64)
    )
    
    # Paper feed (top rectangle)
    paper_height = size // 4
    draw.rectangle(
        [margin * 2, margin, size - margin * 2, body_top + margin],
        fill='#f0f0f0',
        outline='#333333',
        width=max(2, size // 64)
    )
    
    # Scanner light (horizontal line)
    light_y = body_top + size // 6
    draw.line(
        [margin * 2, light_y, size - margin * 2, light_y],
        fill='#10b981',
        width=max(3, size // 32)
    )
    
    # Add emoji if size is large enough
    if size >= 192:
        try:
            # Try to use emoji font (works on most Linux systems)
            font_size = size // 3
            font = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf", font_size)
            emoji = "🖨️"
            
            # Get emoji size
            bbox = draw.textbbox((0, 0), emoji, font=font)
            emoji_width = bbox[2] - bbox[0]
            emoji_height = bbox[3] - bbox[1]
            
            # Center emoji
            x = (size - emoji_width) // 2
            y = (size - emoji_height) // 2
            
            draw.text((x, y), emoji, font=font, embedded_color=True)
        except:
            # Fallback: just use the drawn shape
            pass
    
    img.save(output_path, 'PNG', optimize=True)
    print(f"✅ Created {output_path} ({size}x{size})")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Generate icons
    create_icon(192, os.path.join(script_dir, 'icon-192.png'))
    create_icon(512, os.path.join(script_dir, 'icon-512.png'))
    
    # Also create favicon
    create_icon(32, os.path.join(script_dir, 'favicon.ico'))
    
    print("\n🎨 Icons generiert!")

if __name__ == '__main__':
    main()
