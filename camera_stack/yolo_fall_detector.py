#!/usr/bin/env python3
import argparse, threading, time
from collections import deque
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort

class Camera:
    def __init__(self):
        self.cap = cv2.VideoCapture(0, cv2.CAP_V4L2)
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640); self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        if not self.cap.isOpened(): raise RuntimeError("camera open failed")
        self.frame = None; self.seq = 0; self.lock = threading.Lock(); self.run = True
        self.thread = threading.Thread(target=self.read, daemon=True); self.thread.start()
    def read(self):
        while self.run:
            ok, frame = self.cap.read()
            if ok and frame is not None and frame.size > 0 and frame.ndim == 3 and frame.shape[0] >= 32 and frame.shape[1] >= 32 and frame.shape[2] == 3:
                with self.lock: self.frame, self.seq = frame, self.seq + 1
    def latest(self):
        with self.lock: return self.seq, None if self.frame is None else self.frame.copy()
    def close(self):
        self.run = False; self.thread.join(timeout=1); self.cap.release()

def detect(session, frame, threshold):
    if frame is None or frame.size == 0 or frame.ndim != 3 or frame.shape[2] != 3:
        return []
    h, w = frame.shape[:2]
    if h <= 0 or w <= 0:
        return []
    input_size = int(session.get_inputs()[0].shape[-1])
    if input_size <= 0:
        raise ValueError(f"Invalid YOLO input size: {input_size}")
    scale = min(input_size/w, input_size/h)
    rw, rh = max(1, round(w*scale)), max(1, round(h*scale))
    resized = cv2.resize(frame, (rw, rh)); left, top = (input_size-rw)//2, (input_size-rh)//2
    canvas = np.full((input_size, input_size, 3), 114, np.uint8); canvas[top:top+rh, left:left+rw] = resized
    x = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB).astype(np.float32) / 255
    output = session.run(None, {session.get_inputs()[0].name: x.transpose(2,0,1)[None]})[0]
    predictions = output[0].T
    boxes = predictions[:, :4]
    # COCO class 0 is person. Ultralytics YOLO11 ONNX exports probabilities.
    scores = predictions[:, 4]
    found, confs = [], []
    for score, (cx, cy, bw, bh) in zip(scores, boxes):
        if score < threshold: continue
        x1=max(0,int(((cx-bw/2)-left)/scale)); y1=max(0,int(((cy-bh/2)-top)/scale))
        x2=min(w-1,int(((cx+bw/2)-left)/scale)); y2=min(h-1,int(((cy+bh/2)-top)/scale))
        if x2>x1 and y2>y1: found.append([x1,y1,x2-x1,y2-y1]); confs.append(float(score))
    ids = cv2.dnn.NMSBoxes(found, confs, threshold, .45)
    return [(found[int(i)], confs[int(i)]) for i in np.array(ids).reshape(-1)]

def main():
    p=argparse.ArgumentParser(); p.add_argument('--headless',action='store_true'); p.add_argument('--seconds',type=float,default=0); p.add_argument('--confidence',type=float,default=.35); a=p.parse_args()
    session=ort.InferenceSession('models/yolo11n.onnx',providers=['CPUExecutionProvider']); camera=Camera()
    history=deque(maxlen=12); lying_since=None; candidate_until=alarm_until=0.; last=-1; start=time.monotonic(); out=Path('artifacts/falls'); out.mkdir(parents=True,exist_ok=True)
    try:
        while True:
            seq, frame=camera.latest()
            if frame is None or seq==last: time.sleep(.005); continue
            last=seq; tick=time.monotonic(); people=detect(session,frame,a.confidence); now=time.monotonic(); state='NO PERSON'
            if people:
                (x,y,w,h),conf=max(people,key=lambda z:z[0][2]*z[0][3]); cy=y+h/2; history.append((now,cy)); ratio=w/max(h,1)
                recent=[v for t,v in history if t>now-1.5]; drop=cy-min(recent,default=cy)
                if drop>frame.shape[0]*.12: candidate_until=now+3
                if ratio>1.1:
                    lying_since=lying_since or now; state='LYING'
                    if now-lying_since>1.2 and now<candidate_until:
                        state='FALL DETECTED'
                        if now>=alarm_until:
                            alarm_until=now+10; path=out/f"fall-{time.strftime('%Y%m%d-%H%M%S')}.jpg"; cv2.imwrite(str(path),frame); print(f'FALL_DETECTED {path}',flush=True)
                else: lying_since=None; state='PERSON'
                colour=(0,0,255) if now<alarm_until else (0,255,0); cv2.rectangle(frame,(x,y),(x+w,y+h),colour,2); cv2.putText(frame,f'person {conf:.2f}',(x,max(20,y-6)),0,.55,colour,2)
            cv2.putText(frame,f'{state} | {(now-tick)*1000:.0f} ms',(12,30),0,.7,(0,255,255),2)
            if not a.headless:
                cv2.imshow('YOLO fall detector',frame)
                if cv2.waitKey(1)&255 in (27,ord('q')): break
            if a.seconds and now-start>=a.seconds: break
    finally: camera.close(); cv2.destroyAllWindows()

if __name__=='__main__': main()
