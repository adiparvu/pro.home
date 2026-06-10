export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6 animate-pulse">
      <div className="h-8 w-36 rounded-xl glass-light" />
      <div className="h-11 rounded-xl glass-light" />
      <div className="flex gap-2">
        {[1,2,3,4,5].map((i) => <div key={i} className="h-7 w-16 rounded-full glass-light" />)}
      </div>
      <div className="h-24 rounded-2xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
    </div>
  )
}
