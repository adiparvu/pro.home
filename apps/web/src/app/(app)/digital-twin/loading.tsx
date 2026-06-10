export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-36 rounded-xl glass-light" />
      <div className="grid grid-cols-3 gap-2">
        <div className="h-16 rounded-xl glass-light" />
        <div className="h-16 rounded-xl glass-light" />
        <div className="h-16 rounded-xl glass-light" />
      </div>
      <div className="flex gap-2">
        <div className="h-7 w-20 rounded-full glass-light" />
        <div className="h-7 w-16 rounded-full glass-light" />
      </div>
      <div className="w-full rounded-2xl glass-light" style={{ aspectRatio: '4/3' }} />
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {[1,2,3,4,5,6].map((i) => <div key={i} className="h-24 rounded-xl glass-light" />)}
      </div>
    </div>
  )
}
