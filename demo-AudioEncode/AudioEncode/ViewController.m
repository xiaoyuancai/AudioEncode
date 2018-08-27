//
//  ViewController.m
//  AudioEncode
//
//  Created by Yuan Le on 2018/8/27.
//  Copyright © 2018年 Yuan Le. All rights reserved.
//

#import "ViewController.h"
//核心库
#include "libavcodec/avcodec.h"
//封装格式处理库
#include "libavformat/avformat.h"
//工具库
#include "libavutil/imgutils.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //文件准备
    NSString* inPath = [[NSBundle mainBundle] pathForResource:@"Test" ofType:@"pcm"];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                            NSUserDomainMask,
                                            YES);
    NSString *path = [paths objectAtIndex:0];
    NSString *tmpPath = [path stringByAppendingPathComponent:@"temp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpPath withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString* outFilePath = [tmpPath stringByAppendingPathComponent:[NSString stringWithFormat:@"Test.aac"]];
   
    
    //第一步：注册组件
    av_register_all();
    //第二步：初始化封装格式上下文
    AVFormatContext* avformat_context = avformat_alloc_context();
    //推测输出文件类型（音频采样数据格式类型）aac
    const char* outFilePathChar = [outFilePath UTF8String];
    //得到音频采样数据格式（aac,mp3等等）
    AVOutputFormat* avoutput_format = av_guess_format(NULL, outFilePathChar, NULL);
    //指定类型,必不可少的一步
    avformat_context->oformat = avoutput_format;
    //第三步：打开输出文件
    if (avio_open(&avformat_context->pb, outFilePathChar, AVIO_FLAG_WRITE)<0) {
        NSLog(@"打开输出文件失败");
        return;
    }
    //第四步：创建输出码流（音频流 ）
    AVStream* av_audio_stream = avformat_new_stream(avformat_context, NULL);//只是创建内存，目前不知道是什么类型的流，但是们希望是音频流
    
    //第五步：查找音频编码器
    
    //5.1 获取音频编码器上下文
    AVCodecContext* avcodec_context = av_audio_stream->codec;
    //5.2 设置音频编码器上下文参数
    avcodec_context->codec_id = avoutput_format->audio_codec;//设置音频编码器ID
    avcodec_context->codec_type = AVMEDIA_TYPE_AUDIO ;//设置编码器类型
    avcodec_context->sample_fmt  = AV_SAMPLE_FMT_S16;//设置读取音频采样数据格式pcm（编码的是采样数据格式）,这个类型是根据解码的时候指定的音频采样数据格式类型
    
    //设置采样率
    avcodec_context->sample_rate = 44100;
    //立体声
    avcodec_context->channel_layout = AV_CH_LAYOUT_STEREO;
    //声道数量
    int chanels = av_get_channel_layout_nb_channels(avcodec_context->channel_layout);
    avcodec_context->channels = chanels;
    //设置码率
    //基本算法 码率（kbps） = [视频大小-音频大小](bit位)/[时间](秒)
    avcodec_context->bit_rate = 128000;
    
    //5.3 查找编码器（aac）
    AVCodec* avcodec = avcodec_find_encoder(avcodec_context->codec_id);
    if (avcodec==NULL) {
        NSLog(@"找不到音频编码器");
        return;
    }
    NSLog(@"找到音频编码器:%s ",avcodec->name);
    
    //第六步：打开编码器，打开aac编码器
    if (avcodec_open2(avcodec_context, avcodec, NULL ) < 0) {
        NSLog(@"打开音频编码器失败");
        return;
    }
    
    //第七步：写入文件头信息
    avformat_write_header(avformat_context, NULL);
    
    //打开输入文件
    const char *c_inFilePath = [inPath UTF8String];
    FILE *in_file = fopen(c_inFilePath, "rb");
    if (in_file == NULL) {
        NSLog(@"YUV文件打开失败");
        return;
    }
    
    //初始化音频采样数据帧缓冲区
    AVFrame *av_frame = av_frame_alloc();
    av_frame->nb_samples = avcodec_context->frame_size;
    av_frame->format = avcodec_context->sample_fmt;
    
    //得到音频采样数据缓冲区大小
    int buffer_size = av_samples_get_buffer_size(NULL,
                                                 avcodec_context->channels,
                                                 avcodec_context->frame_size,
                                                 avcodec_context->sample_fmt,
                                                 1);
    
    
    //创建缓冲区->存储音频采样数据->一帧数据
    uint8_t *out_buffer = (uint8_t *) av_malloc(buffer_size);
    avcodec_fill_audio_frame(av_frame,
                             avcodec_context->channels,
                             avcodec_context->sample_fmt,
                             (const uint8_t *)out_buffer,
                             buffer_size,
                             1);
    
    //接收一帧音频采样数据->编码为->aac格式
    AVPacket *av_packet = (AVPacket *) av_malloc(buffer_size);
    
    int frame_current = 1;
    int i = 0, ret = 0;
    
    //第八步：循环编码每一帧音频
    while (true) {
        //1、读取一帧音频采样数据
        if (fread(out_buffer, 1, buffer_size, in_file) <= 0) {
            NSLog(@"Failed to read raw data! \n");
            break;
        } else if (feof(in_file)) {
            break;
        }
        
        //2、设置音频采样数据格式
        //将outbuffer->av_frame格式
        av_frame->data[0] = out_buffer;
        av_frame->pts = i;
        i++;
        
        //第九步:音频编码处理，编码一帧音频采样数据->得到音频采样数据->aac
        //发送一帧音频采样数据
        ret = avcodec_send_frame(avcodec_context, av_frame);
        if (ret != 0) {
            NSLog(@"Failed to send frame! \n");
            return;
        }
        // 接收一帧音频数据->编码为->音频采样数据格式
        ret = avcodec_receive_packet(avcodec_context, av_packet);
        
        if (ret == 0) {
            //编码成功
            //第10步：将音频采样数据->写入到输出文件中->outFilePath
            NSLog(@"当前编码到了第%d帧", frame_current);
            frame_current++;
            av_packet->stream_index = av_audio_stream->index;
            ret = av_write_frame(avformat_context, av_packet);
            if (ret < 0) {
                NSLog(@"写入失败! \n");
                return;
            }
        } else {
            NSLog(@"Failed to encode! \n");
            return;
        }
    }
    
    //第十一步：输入的像素数据读取完成后调用此函数。用于输出编码器中剩余的AVPacket。
    ret = flush_encoder(avformat_context, 0);
    if (ret < 0) {
        NSLog(@"Flushing encoder failed\n");
        return;
    }
    
    //第十二步：写文件尾（对于某些没有文件头的封装格式，不需要此函数。比如说MPEG2TS）
    av_write_trailer(avformat_context);
    
    
    //第十三步：释放内存，关闭编码器
    avcodec_close(avcodec_context);
    av_free(av_frame);
    av_free(out_buffer);
    av_packet_free(&av_packet);
    avio_close(avformat_context->pb);
    avformat_free_context(avformat_context);
    fclose(in_file);
}

int flush_encoder(AVFormatContext *fmt_ctx, unsigned int stream_index) {
    int ret;
    int got_frame;
    AVPacket enc_pkt;
    if (!(fmt_ctx->streams[stream_index]->codec->codec->capabilities &
          CODEC_CAP_DELAY))
        return 0;
    while (1) {
        enc_pkt.data = NULL;
        enc_pkt.size = 0;
        av_init_packet(&enc_pkt);
        ret = avcodec_encode_video2(fmt_ctx->streams[stream_index]->codec, &enc_pkt,
                                    NULL, &got_frame);
        av_frame_free(NULL);
        if (ret < 0)
            break;
        if (!got_frame) {
            ret = 0;
            break;
        }
        NSLog(@"Flush Encoder: Succeed to encode 1 frame!\tsize:%5d\n", enc_pkt.size);
        /* mux encoded frame */
        ret = av_write_frame(fmt_ctx, &enc_pkt);
        if (ret < 0)
            break;
    }
    return ret;
}


@end
