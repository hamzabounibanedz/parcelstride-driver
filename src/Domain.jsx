import React,{useEffect,useRef,useState} from 'react';
import {Geolocation} from '@capacitor/geolocation';
import {MapPanel,depot} from './map';
import {workspace,nav,test} from './platform';
export function Extras(){return null}
export function Actions({item,mutate,data,busy}){
 const mine=data.records.find(r=>r.item===item.id&&r.slot===new Date().toISOString().slice(0,10));
 return <><MapPanel items={[depot,item]} line/><p>Pickup at Union Station dispatch. Drop at {item.detail}.</p><button className="primary wide" {...test('claim')} disabled={busy} onClick={()=>mine?nav('activity'):mutate('claim',{item:item.id},'Assignment claimed',()=>nav('activity'))}>{mine?'Open assignment':'Claim assignment'}</button></>
}
function Run({r,item,mutate}){
 const [recipient,setRecipient]=useState(''),[message,setMessage]=useState(''),[tracking,setTracking]=useState(false);
 const state=useRef({active:false,watch:null,session:0});
 async function stop(){const s=state.current;s.active=false;s.session++;const old=s.watch;s.watch=null;if(old!==null)await Geolocation.clearWatch({id:old}).catch(()=>{});setTracking(false)}
 useEffect(()=>{const hide=()=>{if(document.hidden)stop()};document.addEventListener('visibilitychange',hide);return()=>{document.removeEventListener('visibilitychange',hide);stop()}},[]);
 async function start(){
   if(state.current.active)return;
   const s=state.current;s.active=true;const turn=++s.session;setTracking(true);
   try{
    const granted=await Geolocation.requestPermissions();if(granted.location!=='granted'&&granted.coarseLocation!=='granted')throw new Error('Location permission was declined.');
    if(!s.active||turn!==s.session)return;
    let last=0;
    const watch=await Geolocation.watchPosition({enableHighAccuracy:false,timeout:25000,maximumAge:10000},async(pos,err)=>{
     if(!s.active||turn!==s.session)return;if(err){setMessage(err.message||'Location unavailable');return}
     if(!pos||Date.now()-last<15000)return;last=Date.now();
     try{await workspace('location',{id:r.id,lat:pos.coords.latitude,lng:pos.coords.longitude});if(turn===s.session)setMessage('Position saved at '+new Date(last).toLocaleTimeString())}catch(e){if(turn===s.session)setMessage(e.message)}
    });if(!s.active||turn!==s.session){await Geolocation.clearWatch({id:watch})}else{s.watch=watch}
   }catch(e){if(turn===s.session){await stop();setMessage(e.message)}}
 }
 return <article className="record"><span className="tag">{r.status}</span><h2>{item.title}</h2><p>{item.detail} · {r.slot}</p>
 {r.status==='Assigned'&&<button className="primary" {...test('start')} onClick={()=>mutate('start',{id:r.id},'Route started')}>Start route</button>}
 {r.status==='En route'&&<><MapPanel items={[depot,item]} line/><a href={'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route='+depot.lat+'%2C'+depot.lng+'%3B'+item.lat+'%2C'+item.lng} target="_blank" rel="noreferrer">Open driving directions ↗</a><p className="lean">Location sharing saves the latest position to your assignment while this screen is open. Delivery confirmation clears it.</p><button className="secondary" onClick={tracking?stop:start}>{tracking?'Stop location sharing':'Share my location'}</button><p role="status">{message}</p><form onSubmit={e=>{e.preventDefault();mutate('deliver',{id:r.id,recipient},'Delivery confirmed',stop)}}><label>Received by<input {...test('recipient')} value={recipient} required minLength={2} maxLength={60} onChange={e=>setRecipient(e.target.value)}/></label><button className="primary" {...test('deliver')}>Confirm delivery</button></form></>}
 {r.status==='Delivered'&&<p>Received by {r.payload.recipient} · {new Date(r.payload.completed).toLocaleTimeString()}</p>}</article>
}
export function Records({data,mutate}){return data.records.length?data.records.map(r=><Run key={r.id} r={r} item={data.catalog.find(i=>i.id===r.item)} mutate={mutate}/>):<p className="empty">Claim a dispatch assignment to start your first run.</p>}

