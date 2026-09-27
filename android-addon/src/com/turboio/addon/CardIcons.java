package com.turboio.addon;
import android.graphics.*;

/** Original simple geometric icons, rendered once into bounded monochrome pixels. */
final class CardIcons {
    static final String[] NAMES={"闪光","太阳","电脑","芯片","内存","存储","电池","云","书籍","音乐","位置","计时","心形","完成","趋势","提醒"};
    static byte[] pixels(int index,int size){Bitmap b=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(b);c.scale(size/48f,size/48f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setColor(Color.WHITE);p.setStrokeWidth(3);p.setStyle(Paint.Style.STROKE);p.setStrokeJoin(Paint.Join.ROUND);p.setStrokeCap(Paint.Cap.ROUND);
        switch(index){case 0:Path star=new Path();star.moveTo(24,3);star.lineTo(29,18);star.lineTo(44,24);star.lineTo(29,29);star.lineTo(24,44);star.lineTo(19,29);star.lineTo(4,24);star.lineTo(19,18);star.close();c.drawPath(star,p);break;
        case 1:c.drawCircle(24,24,10,p);for(int i=0;i<8;i++){double a=i*Math.PI/4;c.drawLine(24+(float)Math.cos(a)*16,24+(float)Math.sin(a)*16,24+(float)Math.cos(a)*21,24+(float)Math.sin(a)*21,p);}break;
        case 2:c.drawRoundRect(8,7,40,32,3,3,p);c.drawLine(8,32,3,40,p);c.drawLine(3,40,45,40,p);c.drawLine(45,40,40,32,p);break;
        case 3:c.drawRect(12,12,36,36,p);c.drawRect(19,19,29,29,p);for(int i=16;i<=32;i+=8){c.drawLine(i,5,i,12,p);c.drawLine(i,36,i,43,p);c.drawLine(5,i,12,i,p);c.drawLine(36,i,43,i,p);}break;
        case 4:c.drawRect(5,13,43,34,p);for(int i=11;i<39;i+=9){c.drawRect(i,19,i+4,27,p);c.drawLine(i,34,i,39,p);}break;
        case 5:c.drawRoundRect(8,7,40,41,3,3,p);c.drawCircle(24,22,9,p);c.drawLine(23,24,34,34,p);break;
        case 6:c.drawRoundRect(4,13,40,35,3,3,p);c.drawLine(44,20,44,28,p);p.setStyle(Paint.Style.FILL);c.drawRect(9,18,29,30,p);break;
        case 7:c.drawArc(7,18,25,38,90,180,false,p);c.drawArc(15,7,38,33,180,180,false,p);c.drawArc(28,19,45,38,-90,180,false,p);c.drawLine(16,38,36,38,p);break;
        case 8:c.drawRoundRect(7,7,41,41,3,3,p);c.drawLine(24,7,24,41,p);c.drawLine(11,15,18,15,p);c.drawLine(30,15,37,15,p);break;
        case 9:c.drawLine(19,9,19,35,p);c.drawLine(19,9,39,5,p);c.drawLine(39,5,39,31,p);c.drawOval(6,30,19,41,p);c.drawOval(26,26,39,37,p);break;
        case 10:c.drawCircle(24,19,13,p);c.drawCircle(24,19,4,p);c.drawLine(14,28,24,44,p);c.drawLine(34,28,24,44,p);break;
        case 11:c.drawCircle(24,27,16,p);c.drawLine(19,4,29,4,p);c.drawLine(24,11,24,4,p);c.drawLine(24,27,24,17,p);c.drawLine(24,27,32,27,p);break;
        case 12:Path heart=new Path();heart.moveTo(24,42);heart.cubicTo(-9,20,8,-3,24,13);heart.cubicTo(40,-3,57,20,24,42);c.drawPath(heart,p);break;
        case 13:c.drawCircle(24,24,19,p);c.drawLine(13,24,21,32,p);c.drawLine(21,32,36,16,p);break;
        case 14:c.drawLine(6,6,6,42,p);c.drawLine(6,42,43,42,p);c.drawLine(11,33,20,22,p);c.drawLine(20,22,29,29,p);c.drawLine(29,29,40,10,p);break;
        case 15:Path bell=new Path();bell.moveTo(8,34);bell.lineTo(12,28);bell.lineTo(12,18);bell.cubicTo(12,3,36,3,36,18);bell.lineTo(36,28);bell.lineTo(40,34);bell.close();c.drawPath(bell,p);c.drawArc(18,33,30,43,0,180,false,p);break;default:b.recycle();throw new IllegalArgumentException();}
        int[] pixels=new int[size*size];b.getPixels(pixels,0,size,0,0,size,size);b.recycle();byte[] out=new byte[size*size/8];for(int i=0;i<pixels.length;i++)if(Color.alpha(pixels[i])>=100)out[i/8]|=128>>>(i%8);return out;
    }
}
